// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseIntegrationTest, ITokenStakingNode} from "./BaseIntegrationTest.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {console} from "forge-std/console.sol";
import {CAPAutoPounder} from "../../src/CAPAutoPounder.sol";
import {IRewardsCoordinator} from "../../src/interfaces/IRewardsCoordinator.sol";
import {MainnetContracts} from "../../script/Contracts.sol";
import {MainnetActors} from "../../script/Actors.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

interface IynEigenViewer {
    function getRate() external view returns (uint256);
}

contract CompoundIntegrationTest is BaseIntegrationTest {

    // ============================================
    // Configuration Tests
    // ============================================

    function test_Configuration() public view {
        assertEq(address(autoPounder.rewardsCoordinator()), REWARDS_COORDINATOR);
        assertEq(autoPounder.weth(), WETH);
        assertEq(autoPounder.oeth(), OETH);
        assertEq(address(autoPounder.woeth()), WOETH);
        assertEq(address(autoPounder.oethVault()), OETH_VAULT);
        assertEq(address(autoPounder.redemptionAssetsVault()), REDEMPTION_ASSETS_VAULT);
        assertEq(autoPounder.getRewardTokenCount(), 4);
    }

    function test_StakingNodesClaimerSet() public view {
        address[] memory nodes = _getStakingNodes();
        IRewardsCoordinator rc = IRewardsCoordinator(REWARDS_COORDINATOR);

        for (uint256 i = 0; i < nodes.length; i++) {
            address claimer = rc.claimerFor(nodes[i]);
            assertEq(claimer, address(autoPounder), "Claimer should be CAPAutoPounder");
        }
    }

    // ============================================
    // Compound Tests (with deal'd tokens to simulate)
    // ============================================

    function test_ClaimAndSwap() public {
        // Simulate receiving reward tokens (as if processClaim was called)
        deal(EIGEN, address(autoPounder), 100e18);
        deal(USDC, address(autoPounder), 500e6);
        deal(WETH, address(autoPounder), 1e16); // 0.01 ETH

        console.log("EIGEN balance:", IERC20(EIGEN).balanceOf(address(autoPounder)));
        console.log("USDC balance:", IERC20(USDC).balanceOf(address(autoPounder)));
        console.log("WETH balance:", IERC20(WETH).balanceOf(address(autoPounder)));

        // Call compound with empty claims (tokens already deal'd)
        IRewardsCoordinator.RewardsMerkleClaim[] memory emptyClaims =
            new IRewardsCoordinator.RewardsMerkleClaim[](0);

        vm.prank(compounder);
        autoPounder.compound(emptyClaims, false, 0);

        // Verify tokens were swapped — AutoPounder should have minimal residual
        assertEq(IERC20(EIGEN).balanceOf(address(autoPounder)), 0, "EIGEN should be swapped");
        assertEq(IERC20(USDC).balanceOf(address(autoPounder)), 0, "USDC should be swapped");
        assertEq(IERC20(WETH).balanceOf(address(autoPounder)), 0, "WETH should be used");
    }

    function test_CompoundIncreasesYnLSDeRate() public {
        deal(WETH, address(autoPounder), 10e18);

        // Get rate before
        // ynEigenViewer is deployed alongside ynLSDe
        // For fork tests, we read the rate from the viewer
        uint256 totalAssetsBefore = _getYnLSDeTotalAssets();

        IRewardsCoordinator.RewardsMerkleClaim[] memory emptyClaims =
            new IRewardsCoordinator.RewardsMerkleClaim[](0);

        vm.prank(compounder);
        autoPounder.compound(emptyClaims, false, 0);

        uint256 totalAssetsAfter = _getYnLSDeTotalAssets();
        assertGt(totalAssetsAfter, totalAssetsBefore, "totalAssets should increase after donation");
    }

    function test_CompoundWethOnly() public {
        deal(WETH, address(autoPounder), 1e18);

        uint256 totalAssetsBefore = _getYnLSDeTotalAssets();

        IRewardsCoordinator.RewardsMerkleClaim[] memory emptyClaims =
            new IRewardsCoordinator.RewardsMerkleClaim[](0);

        vm.prank(compounder);
        autoPounder.compound(emptyClaims, false, 0);

        assertEq(IERC20(WETH).balanceOf(address(autoPounder)), 0, "WETH should be used");

        uint256 totalAssetsAfter = _getYnLSDeTotalAssets();
        assertGt(totalAssetsAfter, totalAssetsBefore, "totalAssets should increase");
    }

    function test_CompoundNoTokens() public {
        IRewardsCoordinator.RewardsMerkleClaim[] memory emptyClaims =
            new IRewardsCoordinator.RewardsMerkleClaim[](0);

        // Should not revert even with zero balances
        vm.prank(compounder);
        autoPounder.compound(emptyClaims, false, 0);
    }

    function test_CompoundSlippageProtection() public {
        deal(WETH, address(autoPounder), 1e18);

        IRewardsCoordinator.RewardsMerkleClaim[] memory emptyClaims =
            new IRewardsCoordinator.RewardsMerkleClaim[](0);

        // Should revert when minWethOutput exceeds actual WETH
        vm.prank(compounder);
        vm.expectRevert(
            abi.encodeWithSelector(CAPAutoPounder.SlippageExceeded.selector, 1e18, 2e18)
        );
        autoPounder.compound(emptyClaims, false, 2e18);

        // Should succeed when minWethOutput is met
        vm.prank(compounder);
        autoPounder.compound(emptyClaims, false, 1e18);
    }

    // ============================================
    // Permissioning Tests
    // ============================================

    function test_CompoundRequiresRole() public {
        address nonCompounder = makeAddr("nonCompounder");
        bytes32 compounderRole = autoPounder.COMPOUNDER_ROLE();

        IRewardsCoordinator.RewardsMerkleClaim[] memory emptyClaims =
            new IRewardsCoordinator.RewardsMerkleClaim[](0);

        // Non-compounder should be rejected
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonCompounder,
                compounderRole
            )
        );
        vm.prank(nonCompounder);
        autoPounder.compound(emptyClaims, false, 0);

        // Compounder should succeed
        vm.prank(compounder);
        autoPounder.compound(emptyClaims, false, 0);
    }

    function test_RealizeInterestRequiresRole() public {
        address nonCompounder = makeAddr("nonCompounder");
        bytes32 compounderRole = autoPounder.COMPOUNDER_ROLE();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonCompounder,
                compounderRole
            )
        );
        vm.prank(nonCompounder);
        autoPounder.realizeInterest();

        vm.prank(compounder);
        autoPounder.realizeInterest();
    }

    function test_ClaimOnlyRequiresRole() public {
        address nonCompounder = makeAddr("nonCompounder");
        bytes32 compounderRole = autoPounder.COMPOUNDER_ROLE();

        IRewardsCoordinator.RewardsMerkleClaim[] memory emptyClaims =
            new IRewardsCoordinator.RewardsMerkleClaim[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                nonCompounder,
                compounderRole
            )
        );
        vm.prank(nonCompounder);
        autoPounder.claimOnly(emptyClaims);

        vm.prank(compounder);
        autoPounder.claimOnly(emptyClaims);
    }

    // ============================================
    // Admin Tests
    // ============================================

    function test_OnlyAdminCanUpdateConfig() public {
        address attacker = makeAddr("attacker");
        bytes32 adminRole = autoPounder.DEFAULT_ADMIN_ROLE();

        address[] memory tokens = new address[](0);
        uint24[] memory fees = new uint24[](0);

        CAPAutoPounder.Config memory config = CAPAutoPounder.Config({
            rewardsCoordinator: REWARDS_COORDINATOR,
            capInterestContract: address(0),
            capRestaker: address(0),
            capInterestToken: address(0),
            swapRouter: UNISWAP_V3_ROUTER,
            weth: WETH,
            oeth: OETH,
            woeth: WOETH,
            oethVault: OETH_VAULT,
            redemptionAssetsVault: REDEMPTION_ASSETS_VAULT,
            rewardTokens: tokens,
            swapPoolFees: fees
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                adminRole
            )
        );
        vm.prank(attacker);
        autoPounder.updateConfig(config);
    }

    function test_AdminCanUpdateConfig() public {
        address[] memory tokens = new address[](1);
        tokens[0] = EIGEN;
        uint24[] memory fees = new uint24[](1);
        fees[0] = MainnetContracts.FEE_MEDIUM;

        CAPAutoPounder.Config memory config = CAPAutoPounder.Config({
            rewardsCoordinator: REWARDS_COORDINATOR,
            capInterestContract: CAP_INTEREST_CONTRACT,
            capRestaker: CAP_RESTAKER_SAFE,
            capInterestToken: USDC,
            swapRouter: UNISWAP_V3_ROUTER,
            weth: WETH,
            oeth: OETH,
            woeth: WOETH,
            oethVault: OETH_VAULT,
            redemptionAssetsVault: REDEMPTION_ASSETS_VAULT,
            rewardTokens: tokens,
            swapPoolFees: fees
        });

        vm.prank(admin);
        autoPounder.updateConfig(config);

        assertEq(autoPounder.getRewardTokenCount(), 1);
    }

    function test_RecoverToken() public {
        deal(USDC, address(autoPounder), 1000e6);

        uint256 initialBalance = IERC20(USDC).balanceOf(admin);

        vm.prank(admin);
        autoPounder.recoverToken(USDC, 1000e6, admin);

        assertEq(
            IERC20(USDC).balanceOf(admin) - initialBalance,
            1000e6,
            "Should recover tokens"
        );
    }

    function test_RecoverTokenInvalidDestination() public {
        deal(USDC, address(autoPounder), 1000e6);

        vm.prank(admin);
        vm.expectRevert(CAPAutoPounder.InvalidDestination.selector);
        autoPounder.recoverToken(USDC, 1000e6, address(0));
    }

    // ============================================
    // Realize Interest Tests
    // ============================================

    function test_RealizeInterest() public {
        // Should not revert even if the CAP call fails
        vm.prank(compounder);
        autoPounder.realizeInterest();
    }

    function test_ClaimOnly() public {
        IRewardsCoordinator.RewardsMerkleClaim[] memory emptyClaims =
            new IRewardsCoordinator.RewardsMerkleClaim[](0);

        vm.prank(compounder);
        autoPounder.claimOnly(emptyClaims);
    }

    // ============================================
    // Constructor Validation Tests
    // ============================================

    function test_ConstructorInvalidAdmin() public {
        address[] memory tokens = new address[](0);
        uint24[] memory fees = new uint24[](0);

        CAPAutoPounder.Config memory config = CAPAutoPounder.Config({
            rewardsCoordinator: REWARDS_COORDINATOR,
            capInterestContract: address(0),
            capRestaker: address(0),
            capInterestToken: address(0),
            swapRouter: UNISWAP_V3_ROUTER,
            weth: WETH,
            oeth: OETH,
            woeth: WOETH,
            oethVault: OETH_VAULT,
            redemptionAssetsVault: REDEMPTION_ASSETS_VAULT,
            rewardTokens: tokens,
            swapPoolFees: fees
        });

        vm.expectRevert(CAPAutoPounder.InvalidAddress.selector);
        new CAPAutoPounder(config, address(0));
    }

    function test_ConstructorArrayLengthMismatch() public {
        address[] memory tokens = new address[](2);
        tokens[0] = EIGEN;
        tokens[1] = USDC;
        uint24[] memory fees = new uint24[](1);
        fees[0] = MainnetContracts.FEE_MEDIUM;

        CAPAutoPounder.Config memory config = CAPAutoPounder.Config({
            rewardsCoordinator: REWARDS_COORDINATOR,
            capInterestContract: address(0),
            capRestaker: address(0),
            capInterestToken: address(0),
            swapRouter: UNISWAP_V3_ROUTER,
            weth: WETH,
            oeth: OETH,
            woeth: WOETH,
            oethVault: OETH_VAULT,
            redemptionAssetsVault: REDEMPTION_ASSETS_VAULT,
            rewardTokens: tokens,
            swapPoolFees: fees
        });

        vm.expectRevert(CAPAutoPounder.ArrayLengthMismatch.selector);
        new CAPAutoPounder(config, admin);
    }

    // ============================================
    // Helpers
    // ============================================

    function _getYnLSDeTotalAssets() internal view returns (uint256) {
        (bool success, bytes memory data) = YN_LSDE.staticcall(abi.encodeWithSignature("totalAssets()"));
        require(success, "totalAssets call failed");
        return abi.decode(data, (uint256));
    }
}
