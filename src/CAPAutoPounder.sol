// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IRewardsCoordinator} from "./interfaces/IRewardsCoordinator.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IOETHVaultCore} from "./interfaces/IOETHVaultCore.sol";
import {IERC4626} from "./interfaces/IERC4626.sol";
import {IRedemptionAssetsVault} from "./interfaces/IRedemptionAssetsVault.sol";
import {ICAPInterest} from "./interfaces/ICAPInterest.sol";

/**
 * @title CAPAutoPounder
 * @notice Automates EigenLayer reward claiming and compounding into ynLSDe for CAP restaking positions.
 * @dev Workflow:
 *   1. (Optional) Realize CAP restaker interest to notify EigenLayer
 *   2. Claim accumulated rewards from EigenLayer RewardsCoordinator (EIGEN, WETH, USDC, etc.)
 *   3. Swap reward tokens to WETH via Uniswap V3
 *   4. Mint oETH from WETH via OETHVault, then wrap to wOETH
 *   5. Donate wOETH to ynLSDe via RedemptionAssetsVault (increases share rate, no new shares minted)
 *
 * This contract must be set as the `claimer` for each TokenStakingNode via setClaimer().
 * Merkle proofs are generated off-chain by a keeper and passed to compound().
 */
contract CAPAutoPounder is AccessControlEnumerable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================================
    // Roles
    // ============================================

    bytes32 public constant COMPOUNDER_ROLE = keccak256("COMPOUNDER_ROLE");

    // ============================================
    // Structs
    // ============================================

    struct Config {
        address rewardsCoordinator; // EigenLayer RewardsCoordinator
        address capInterestContract; // CAP contract for realizeRestakerInterest
        address capRestaker; // Safe address that restakes into CAP
        address capInterestToken; // Token for CAP interest (e.g., USDC)
        address swapRouter; // Uniswap V3 SwapRouter
        address weth; // WETH address
        address oeth; // oETH address
        address woeth; // wOETH address (ERC4626 over oETH)
        address oethVault; // OETHVaultCore for minting oETH from WETH
        address redemptionAssetsVault; // ynLSDe RedemptionAssetsVault for donation
        address[] rewardTokens; // Tokens to swap (EIGEN, USDC, ARPA, etc.)
        uint24[] swapPoolFees; // Uniswap V3 pool fees per reward token
    }

    // ============================================
    // Errors
    // ============================================

    error InvalidAddress();
    error InvalidDestination();
    error Unauthorized();
    error SlippageExceeded(uint256 actual, uint256 minimum);
    error OETHMintSlippage(uint256 oethReceived, uint256 minExpected);
    error ArrayLengthMismatch();
    error MinPerSwapOutputsLengthMismatch();

    // ============================================
    // Events
    // ============================================

    event RewardsClaimed(uint256 claimCount);
    event CAPInterestRealized(address indexed restaker, address indexed token);
    event CAPInterestRealizeFailed(address indexed restaker, address indexed token);
    event TokenSwapped(address indexed token, uint256 amountIn, uint256 amountOut);
    event OETHMinted(uint256 wethAmount, uint256 oethReceived);
    event DonatedToYnLSDe(uint256 woethAmount);
    event TokenRecovered(address indexed token, uint256 amount, address indexed destination);
    event ConfigUpdated();

    // ============================================
    // State Variables
    // ============================================

    IRewardsCoordinator public rewardsCoordinator;
    ICAPInterest public capInterestContract;
    address public capRestaker;
    address public capInterestToken;
    ISwapRouter public swapRouter;
    address public weth;
    address public oeth;
    IERC4626 public woeth;
    IOETHVaultCore public oethVault;
    IRedemptionAssetsVault public redemptionAssetsVault;

    // Reward token swap configuration
    address[] public rewardTokens;
    mapping(address => uint24) public swapPoolFees; // token => Uniswap V3 fee tier

    // ============================================
    // Constructor
    // ============================================

    constructor(Config memory config, address admin) {
        if (admin == address(0)) revert InvalidAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _applyConfig(config);
    }

    // ============================================
    // External Functions
    // ============================================

    /**
     * @notice Executes the full auto-compounding workflow.
     * @dev Merkle proofs must be generated off-chain and passed in.
     *      Only COMPOUNDER_ROLE holders can call this function.
     * @param claims EigenLayer merkle claims for each staking node earner
     * @param shouldRealizeInterest Whether to call realizeRestakerInterest on CAP first
     * @param minWethOutput Minimum total WETH expected after all swaps (keeper-calculated, anti-sandwich)
     * @param minPerSwapOutputs Per-token minimum WETH output from each swap (maps 1:1 to rewardTokens array)
     */
    function compound(
        IRewardsCoordinator.RewardsMerkleClaim[] calldata claims,
        bool shouldRealizeInterest,
        uint256 minWethOutput,
        uint256[] calldata minPerSwapOutputs
    ) external nonReentrant onlyRole(COMPOUNDER_ROLE) {
        // Step 1: Optionally realize CAP interest
        if (shouldRealizeInterest && address(capInterestContract) != address(0)) {
            _realizeInterest();
        }

        // Step 2: Claim rewards from EigenLayer for each staking node
        if (claims.length > 0) {
            _claimRewards(claims);
        }

        // Step 3: Swap all reward tokens to WETH (with per-swap slippage protection)
        uint256 totalWeth = _swapAllRewardsToWeth(minPerSwapOutputs);

        // Step 4: Enforce keeper-provided slippage check on total WETH output
        if (totalWeth < minWethOutput) {
            revert SlippageExceeded(totalWeth, minWethOutput);
        }

        // Step 5: Mint oETH from WETH, then wrap to wOETH
        uint256 woethAmount = 0;
        if (totalWeth > 0) {
            woethAmount = _mintAndWrapToWoeth(totalWeth);
        }

        // Step 6: Donate wOETH to ynLSDe (increases share rate for all holders)
        if (woethAmount > 0) {
            _donateToYnLSDe(woethAmount);
        }
    }

    /**
     * @notice Realize CAP interest only (no claiming or compounding).
     */
    function realizeInterest() external onlyRole(COMPOUNDER_ROLE) {
        if (address(capInterestContract) == address(0)) revert InvalidAddress();
        _realizeInterest();
    }

    /**
     * @notice Claim EigenLayer rewards only (no swapping or depositing).
     */
    function claimOnly(IRewardsCoordinator.RewardsMerkleClaim[] calldata claims)
        external
        nonReentrant
        onlyRole(COMPOUNDER_ROLE)
    {
        _claimRewards(claims);
    }

    // ============================================
    // Admin Functions
    // ============================================

    function updateConfig(Config memory config) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _applyConfig(config);
        emit ConfigUpdated();
    }

    function recoverToken(address token, uint256 amount, address destination) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (destination == address(0)) revert InvalidDestination();
        IERC20(token).safeTransfer(destination, amount);
        emit TokenRecovered(token, amount, destination);
    }

    // ============================================
    // View Functions
    // ============================================

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    function getRewardTokenCount() external view returns (uint256) {
        return rewardTokens.length;
    }

    // ============================================
    // Internal Functions
    // ============================================

    /**
     * @dev Call realizeRestakerInterest on CAP contract.
     *      Does not revert on failure since interest realization may not always be needed.
     */
    function _realizeInterest() internal {
        try capInterestContract.realizeRestakerInterest(capRestaker, capInterestToken) {
            emit CAPInterestRealized(capRestaker, capInterestToken);
        } catch {
            emit CAPInterestRealizeFailed(capRestaker, capInterestToken);
        }
    }

    /**
     * @dev Claim rewards from EigenLayer RewardsCoordinator.
     *      This contract must be the designated claimer for each earner (staking node).
     */
    function _claimRewards(IRewardsCoordinator.RewardsMerkleClaim[] calldata claims) internal {
        for (uint256 i = 0; i < claims.length; i++) {
            rewardsCoordinator.processClaim(claims[i], address(this));
        }
        emit RewardsClaimed(claims.length);
    }

    /**
     * @dev Swap all reward token balances to WETH via Uniswap V3.
     *      Uses per-swap minimums to prevent sandwich attacks on individual tokens.
     *      Returns the total WETH balance after all swaps (claimed + swapped).
     * @param minPerSwapOutputs Per-token minimum output, maps 1:1 to rewardTokens array
     */
    function _swapAllRewardsToWeth(uint256[] calldata minPerSwapOutputs) internal returns (uint256) {
        if (minPerSwapOutputs.length != rewardTokens.length) revert MinPerSwapOutputsLengthMismatch();

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];

            // Skip WETH — already in the right denomination
            if (token == weth) continue;

            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance == 0) continue;

            uint24 fee = swapPoolFees[token];
            if (fee == 0) continue; // Skip tokens without configured swap path

            IERC20(token).forceApprove(address(swapRouter), balance);

            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: token,
                tokenOut: weth,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: balance,
                amountOutMinimum: minPerSwapOutputs[i],
                sqrtPriceLimitX96: 0
            });

            uint256 amountOut = swapRouter.exactInputSingle(params);

            emit TokenSwapped(token, balance, amountOut);
        }

        // Return total WETH balance (claimed WETH + all swap outputs)
        return IERC20(weth).balanceOf(address(this));
    }

    /**
     * @dev Mint oETH from WETH via OETHVault, then wrap oETH into wOETH.
     *      WETH → OETHVault.mint() → oETH → wOETH.deposit() → wOETH
     *      Includes 0.1% tolerance check on oETH mint (1:1 rate is a protocol invariant).
     */
    function _mintAndWrapToWoeth(uint256 wethAmount) internal returns (uint256) {
        // Mint oETH from WETH via OETHVault (1:1 rate)
        IERC20(weth).forceApprove(address(oethVault), wethAmount);

        uint256 oethBalanceBefore = IERC20(oeth).balanceOf(address(this));
        uint256 minOeth = wethAmount * 9990 / 10000; // 0.1% tolerance for rounding
        oethVault.mint(weth, wethAmount, minOeth);
        uint256 oethReceived = IERC20(oeth).balanceOf(address(this)) - oethBalanceBefore;

        if (oethReceived < minOeth) {
            revert OETHMintSlippage(oethReceived, minOeth);
        }

        emit OETHMinted(wethAmount, oethReceived);

        // Wrap oETH into wOETH (deterministic ERC4626 conversion)
        IERC20(oeth).forceApprove(address(woeth), oethReceived);
        uint256 woethReceived = woeth.deposit(oethReceived, address(this));

        return woethReceived;
    }

    /**
     * @dev Donate wOETH to ynLSDe by depositing into RedemptionAssetsVault.
     *      This increases ynLSDe's totalAssets() without minting new shares,
     *      effectively increasing the share rate for all existing holders.
     */
    function _donateToYnLSDe(uint256 woethAmount) internal {
        IERC20(address(woeth)).forceApprove(address(redemptionAssetsVault), woethAmount);
        redemptionAssetsVault.deposit(woethAmount, address(woeth));
        emit DonatedToYnLSDe(woethAmount);
    }

    /**
     * @dev Apply configuration to state variables.
     */
    function _applyConfig(Config memory config) internal {
        if (config.rewardsCoordinator == address(0)) revert InvalidAddress();
        if (config.swapRouter == address(0)) revert InvalidAddress();
        if (config.weth == address(0)) revert InvalidAddress();
        if (config.oeth == address(0)) revert InvalidAddress();
        if (config.woeth == address(0)) revert InvalidAddress();
        if (config.oethVault == address(0)) revert InvalidAddress();
        if (config.redemptionAssetsVault == address(0)) revert InvalidAddress();
        if (config.rewardTokens.length != config.swapPoolFees.length) revert ArrayLengthMismatch();

        rewardsCoordinator = IRewardsCoordinator(config.rewardsCoordinator);
        capInterestContract = ICAPInterest(config.capInterestContract);
        capRestaker = config.capRestaker;
        capInterestToken = config.capInterestToken;
        swapRouter = ISwapRouter(config.swapRouter);
        weth = config.weth;
        oeth = config.oeth;
        woeth = IERC4626(config.woeth);
        oethVault = IOETHVaultCore(config.oethVault);
        redemptionAssetsVault = IRedemptionAssetsVault(config.redemptionAssetsVault);

        // Clear old reward tokens
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            delete swapPoolFees[rewardTokens[i]];
        }
        delete rewardTokens;

        // Set new reward tokens
        for (uint256 i = 0; i < config.rewardTokens.length; i++) {
            rewardTokens.push(config.rewardTokens[i]);
            swapPoolFees[config.rewardTokens[i]] = config.swapPoolFees[i];
        }
    }
}
