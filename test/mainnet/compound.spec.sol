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
        assertEq(address(autoPounder.depositAdapter()), DEPOSIT_ADAPTER);
        assertEq(autoPounder.recipient(), admin);
        assertEq(autoPounder.getRewardTokenCount(), 4);
    }

    function test_StakingNodesClaimerSet() public view {
        address[] memory nodes = MainnetContracts.getStakingNodes();
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

        uint256 initialYnLSDeBalance = IERC20(MainnetContracts.YN_LSDE).balanceOf(admin);

        console.log("EIGEN balance:", IERC20(EIGEN).balanceOf(address(autoPounder)));
        console.log("USDC balance:", IERC20(USDC).balanceOf(address(autoPounder)));
        console.log("WETH balance:", IERC20(WETH).balanceOf(address(autoPounder)));

        // Call compound with empty claims (tokens already deal'd)
        IRewardsCoordinator.RewardsMerkleClaim[] memory emptyClaims =
            new IRewardsCoordinator.RewardsMerkleClaim[](0);

        autoPounder.compound(emptyClaims, false, 0);

        // Verify tokens were swapped — AutoPounder should have minimal residual
        assertEq(IERC20(EIGEN).balanceOf(address(autoPounder)), 0, "EIGEN should be swapped");
        assertEq(IERC20(USDC).balanceOf(address(autoPounder)), 0, "USDC should be swapped");
        assertEq(IERC20(WETH).balanceOf(address(autoPounder)), 0, "WETH should be used");

        // Verify ynLSDe shares were received
        uint256 finalYnLSDeBalance = IERC20(MainnetContracts.YN_LSDE).balanceOf(admin);
        assertGt(finalYnLSDeBalance, initialYnLSDeBalance, "Should have received ynLSDe shares");

        console.log("ynLSDe shares gained:", finalYnLSDeBalance - initialYnLSDeBalance);
    }

    function test_CompoundWethOnly() public {
        deal(WETH, address(autoPounder), 1e18);

        uint256 initialYnLSDeBalance = IERC20(MainnetContracts.YN_LSDE).balanceOf(admin);

        IRewardsCoordinator.RewardsMerkleClaim[] memory emptyClaims =
            new IRewardsCoordinator.RewardsMerkleClaim[](0);

        autoPounder.compound(emptyClaims, false, 0);

        assertEq(IERC20(WETH).balanceOf(address(autoPounder)), 0, "WETH should be used");

        uint256 finalYnLSDeBalance = IERC20(MainnetContracts.YN_LSDE).balanceOf(admin);
        assertGt(finalYnLSDeBalance, initialYnLSDeBalance, "Should have received ynLSDe shares");
    }

    function test_CompoundNoTokens() public {
        IRewardsCoordinator.RewardsMerkleClaim[] memory emptyClaims =
            new IRewardsCoordinator.RewardsMerkleClaim[](0);

        // Should not revert even with zero balances
        autoPounder.compound(emptyClaims, false, 0);
    }

    function test_CompoundSlippageProtection() public {
        deal(WETH, address(autoPounder), 1e18);

        IRewardsCoordinator.RewardsMerkleClaim[] memory emptyClaims =
            new IRewardsCoordinator.RewardsMerkleClaim[](0);

        // Should revert when minWethOutput exceeds actual WETH
        vm.expectRevert(
            abi.encodeWithSelector(CAPAutoPounder.SlippageExceeded.selector, 1e18, 2e18)
        );
        autoPounder.compound(emptyClaims, false, 2e18);

        // Should succeed when minWethOutput is met
        autoPounder.compound(emptyClaims, false, 1e18);
    }

    // ============================================
    // Permissioning Tests
    // ============================================

    function test_CompoundPermissionless() public {
        address randomUser = makeAddr("randomUser");
        bytes32 compounderRole = autoPounder.COMPOUNDER_ROLE();

        assertEq(autoPounder.getRoleMemberCount(compounderRole), 0);

        IRewardsCoordinator.RewardsMerkleClaim[] memory emptyClaims =
            new IRewardsCoordinator.RewardsMerkleClaim[](0);

        vm.prank(randomUser);
        autoPounder.compound(emptyClaims, false, 0);
    }

    function test_CompoundRequiresRole() public {
        address compounder = makeAddr("compounder");
        address nonCompounder = makeAddr("nonCompounder");

        vm.prank(admin);
        autoPounder.grantRole(autoPounder.COMPOUNDER_ROLE(), compounder);

        IRewardsCoordinator.RewardsMerkleClaim[] memory emptyClaims =
            new IRewardsCoordinator.RewardsMerkleClaim[](0);

        vm.prank(nonCompounder);
        vm.expectRevert(CAPAutoPounder.Unauthorized.selector);
        autoPounder.compound(emptyClaims, false, 0);

        vm.prank(compounder);
        autoPounder.compound(emptyClaims, false, 0);
    }

    function test_RealizeInterestRequiresRole() public {
        address compounder = makeAddr("compounder");
        address nonCompounder = makeAddr("nonCompounder");

        vm.prank(admin);
        autoPounder.grantRole(autoPounder.COMPOUNDER_ROLE(), compounder);

        vm.prank(nonCompounder);
        vm.expectRevert(CAPAutoPounder.Unauthorized.selector);
        autoPounder.realizeInterest();

        vm.prank(compounder);
        autoPounder.realizeInterest();
    }

    function test_ClaimOnlyRequiresRole() public {
        address compounder = makeAddr("compounder");
        address nonCompounder = makeAddr("nonCompounder");

        vm.prank(admin);
        autoPounder.grantRole(autoPounder.COMPOUNDER_ROLE(), compounder);

        IRewardsCoordinator.RewardsMerkleClaim[] memory emptyClaims =
            new IRewardsCoordinator.RewardsMerkleClaim[](0);

        vm.prank(nonCompounder);
        vm.expectRevert(CAPAutoPounder.Unauthorized.selector);
        autoPounder.claimOnly(emptyClaims);

        vm.prank(compounder);
        autoPounder.claimOnly(emptyClaims);
    }

    // ============================================
    // Admin Tests
    // ============================================

    function test_OnlyAdminCanUpdateConfig() public {
        address attacker = makeAddr("attacker");

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
            depositAdapter: DEPOSIT_ADAPTER,
            recipient: admin,
            rewardTokens: tokens,
            swapPoolFees: fees
        });

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                autoPounder.DEFAULT_ADMIN_ROLE()
            )
        );
        autoPounder.updateConfig(config);
    }

    function test_AdminCanUpdateConfig() public {
        address[] memory tokens = new address[](1);
        tokens[0] = EIGEN;
        uint24[] memory fees = new uint24[](1);
        fees[0] = MainnetContracts.FEE_MEDIUM;

        address newRecipient = makeAddr("newRecipient");

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
            depositAdapter: DEPOSIT_ADAPTER,
            recipient: newRecipient,
            rewardTokens: tokens,
            swapPoolFees: fees
        });

        vm.prank(admin);
        autoPounder.updateConfig(config);

        assertEq(autoPounder.recipient(), newRecipient);
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
        autoPounder.realizeInterest();
    }

    function test_ClaimOnly() public {
        IRewardsCoordinator.RewardsMerkleClaim[] memory emptyClaims =
            new IRewardsCoordinator.RewardsMerkleClaim[](0);

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
            depositAdapter: DEPOSIT_ADAPTER,
            recipient: admin,
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
            depositAdapter: DEPOSIT_ADAPTER,
            recipient: admin,
            rewardTokens: tokens,
            swapPoolFees: fees
        });

        vm.expectRevert(CAPAutoPounder.ArrayLengthMismatch.selector);
        new CAPAutoPounder(config, admin);
    }
}
