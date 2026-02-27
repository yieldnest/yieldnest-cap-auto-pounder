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
import {IDepositAdapter} from "./interfaces/IDepositAdapter.sol";

/**
 * @title CAPAutoPounder
 * @notice Automates EigenLayer reward claiming and compounding into ynLSDe for CAP restaking positions.
 * @dev Workflow:
 *   1. (Optional) Realize CAP restaker interest to notify EigenLayer
 *   2. Claim accumulated rewards from EigenLayer RewardsCoordinator (EIGEN, WETH, USDC, etc.)
 *   3. Swap reward tokens to WETH via Uniswap V3
 *   4. Mint oETH from WETH via OETHVault, then wrap to wOETH
 *   5. Deposit wOETH into ynLSDe via DepositAdapter
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
        address depositAdapter; // ynLSDe DepositAdapter
        address recipient; // Where ynLSDe shares go (treasury/vault)
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
    error DepositFailed();
    error ArrayLengthMismatch();

    // ============================================
    // Events
    // ============================================

    event RewardsClaimed(uint256 claimCount);
    event CAPInterestRealized(address indexed restaker, address indexed token);
    event CAPInterestRealizeFailed(address indexed restaker, address indexed token);
    event TokenSwapped(address indexed token, uint256 amountIn, uint256 amountOut);
    event OETHMinted(uint256 wethAmount, uint256 oethReceived);
    event DepositedToYnLSDe(uint256 woethAmount, uint256 shares);
    event TokenRecovered(address indexed token, uint256 amount, address indexed destination);
    event ConfigUpdated();

    // ============================================
    // State Variables
    // ============================================

    IRewardsCoordinator public rewardsCoordinator;
    address public capInterestContract;
    address public capRestaker;
    address public capInterestToken;
    ISwapRouter public swapRouter;
    address public weth;
    address public oeth;
    IERC4626 public woeth;
    IOETHVaultCore public oethVault;
    IDepositAdapter public depositAdapter;
    address public recipient;

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
     *      If COMPOUNDER_ROLE has members, only those addresses can call.
     *      If no COMPOUNDER_ROLE members exist, anyone can call.
     * @param claims EigenLayer merkle claims for each staking node earner
     * @param shouldRealizeInterest Whether to call realizeRestakerInterest on CAP first
     * @param minWethOutput Minimum total WETH expected after all swaps (keeper-calculated, anti-sandwich)
     */
    function compound(
        IRewardsCoordinator.RewardsMerkleClaim[] calldata claims,
        bool shouldRealizeInterest,
        uint256 minWethOutput
    ) external nonReentrant {
        _checkCompounderAuth();

        // Step 1: Optionally realize CAP interest
        if (shouldRealizeInterest && capInterestContract != address(0)) {
            _realizeInterest();
        }

        // Step 2: Claim rewards from EigenLayer for each staking node
        if (claims.length > 0) {
            _claimRewards(claims);
        }

        // Step 3: Swap all reward tokens to WETH
        uint256 totalWeth = _swapAllRewardsToWeth();

        // Step 4: Enforce keeper-provided slippage check on total WETH output
        if (totalWeth < minWethOutput) {
            revert SlippageExceeded(totalWeth, minWethOutput);
        }

        // Step 5: Mint oETH from WETH, then wrap to wOETH
        uint256 woethAmount = 0;
        if (totalWeth > 0) {
            woethAmount = _mintAndWrapToWoeth(totalWeth);
        }

        // Step 6: Deposit wOETH into ynLSDe
        if (woethAmount > 0) {
            _depositToYnLSDe(woethAmount);
        }
    }

    /**
     * @notice Realize CAP interest only (no claiming or compounding).
     */
    function realizeInterest() external {
        _checkCompounderAuth();
        if (capInterestContract == address(0)) revert InvalidAddress();
        _realizeInterest();
    }

    /**
     * @notice Claim EigenLayer rewards only (no swapping or depositing).
     */
    function claimOnly(IRewardsCoordinator.RewardsMerkleClaim[] calldata claims) external nonReentrant {
        _checkCompounderAuth();
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

    function _checkCompounderAuth() internal view {
        if (getRoleMemberCount(COMPOUNDER_ROLE) > 0 && !hasRole(COMPOUNDER_ROLE, msg.sender)) {
            revert Unauthorized();
        }
    }

    /**
     * @dev Call realizeRestakerInterest on CAP contract.
     *      Does not revert on failure since interest realization may not always be needed.
     */
    function _realizeInterest() internal {
        (bool success,) = capInterestContract.call(
            abi.encodeWithSignature(
                "realizeRestakerInterest(address,address)",
                capRestaker,
                capInterestToken
            )
        );
        if (success) {
            emit CAPInterestRealized(capRestaker, capInterestToken);
        } else {
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
     *      Returns the total WETH balance after all swaps (claimed + swapped).
     */
    function _swapAllRewardsToWeth() internal returns (uint256) {
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
                amountOutMinimum: 0, // Aggregate slippage enforced via compound()'s minWethOutput
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
     *      Slippage protection is handled at the compound() level via minWethOutput.
     */
    function _mintAndWrapToWoeth(uint256 wethAmount) internal returns (uint256) {
        // Mint oETH from WETH via OETHVault (1:1 rate)
        IERC20(weth).forceApprove(address(oethVault), wethAmount);

        uint256 oethBalanceBefore = IERC20(oeth).balanceOf(address(this));
        oethVault.mint(weth, wethAmount, 0);
        uint256 oethReceived = IERC20(oeth).balanceOf(address(this)) - oethBalanceBefore;

        emit OETHMinted(wethAmount, oethReceived);

        // Wrap oETH into wOETH (deterministic ERC4626 conversion)
        IERC20(oeth).forceApprove(address(woeth), oethReceived);
        uint256 woethReceived = woeth.deposit(oethReceived, address(this));

        return woethReceived;
    }

    /**
     * @dev Deposit wOETH into ynLSDe via DepositAdapter.
     */
    function _depositToYnLSDe(uint256 woethAmount) internal {
        IERC20(address(woeth)).forceApprove(address(depositAdapter), woethAmount);

        uint256 shares = depositAdapter.deposit(address(woeth), woethAmount, recipient);
        if (shares == 0) revert DepositFailed();

        emit DepositedToYnLSDe(woethAmount, shares);
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
        if (config.depositAdapter == address(0)) revert InvalidAddress();
        if (config.recipient == address(0)) revert InvalidAddress();
        if (config.rewardTokens.length != config.swapPoolFees.length) revert ArrayLengthMismatch();

        rewardsCoordinator = IRewardsCoordinator(config.rewardsCoordinator);
        capInterestContract = config.capInterestContract;
        capRestaker = config.capRestaker;
        capInterestToken = config.capInterestToken;
        swapRouter = ISwapRouter(config.swapRouter);
        weth = config.weth;
        oeth = config.oeth;
        woeth = IERC4626(config.woeth);
        oethVault = IOETHVaultCore(config.oethVault);
        depositAdapter = IDepositAdapter(config.depositAdapter);
        recipient = config.recipient;

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
