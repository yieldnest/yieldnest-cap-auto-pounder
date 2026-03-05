// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CAPAutoPounder} from "../../src/CAPAutoPounder.sol";
import {MainnetContracts} from "../../script/Contracts.sol";
import {MainnetActors} from "../../script/Actors.sol";
import {IRewardsCoordinator} from "../../src/interfaces/IRewardsCoordinator.sol";

interface ITokenStakingNode {
    function setClaimer(address claimer) external;
    function delegatedTo() external view returns (address);
    function nodeId() external view returns (uint256);
}

interface ITokenStakingNodesManager {
    function getAllNodes() external view returns (address[] memory);
    function rewardsCoordinator() external view returns (address);
}

contract BaseIntegrationTest is Test {
    CAPAutoPounder public autoPounder;

    // Import addresses
    address constant REWARDS_COORDINATOR = MainnetContracts.REWARDS_COORDINATOR;
    address constant YN_LSDE = MainnetContracts.YN_LSDE;
    address constant TOKEN_STAKING_NODES_MANAGER = MainnetContracts.TOKEN_STAKING_NODES_MANAGER;
    address constant REDEMPTION_ASSETS_VAULT = MainnetContracts.REDEMPTION_ASSETS_VAULT;
    address constant WETH = MainnetContracts.WETH;
    address constant OETH = MainnetContracts.OETH;
    address constant WOETH = MainnetContracts.WOETH;
    address constant OETH_VAULT = MainnetContracts.OETH_VAULT;
    address constant EIGEN = MainnetContracts.EIGEN;
    address constant USDC = MainnetContracts.USDC;
    address constant ARPA = MainnetContracts.ARPA;
    address constant UNISWAP_V3_ROUTER = MainnetContracts.UNISWAP_V3_ROUTER;
    address constant CAP_INTEREST_CONTRACT = MainnetContracts.CAP_INTEREST_CONTRACT;
    address constant CAP_RESTAKER_SAFE = MainnetContracts.CAP_RESTAKER_SAFE;

    address admin;
    address compounder;

    function setUp() public virtual {
        admin = MainnetActors.ADMIN;
        compounder = makeAddr("compounder");

        // Build reward tokens array
        address[] memory rewardTokens = new address[](4);
        rewardTokens[0] = EIGEN;
        rewardTokens[1] = WETH;
        rewardTokens[2] = USDC;
        rewardTokens[3] = ARPA;

        // Fee tiers for Uniswap V3 swaps to WETH
        uint24[] memory fees = new uint24[](4);
        fees[0] = MainnetContracts.FEE_MEDIUM; // EIGEN/WETH 0.3%
        fees[1] = 0; // WETH — no swap needed
        fees[2] = MainnetContracts.FEE_LOW; // USDC/WETH 0.05%
        fees[3] = MainnetContracts.FEE_HIGH; // ARPA/WETH 1%

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
            rewardTokens: rewardTokens,
            swapPoolFees: fees
        });

        autoPounder = new CAPAutoPounder(config, admin);

        // Grant COMPOUNDER_ROLE to our test compounder
        vm.prank(admin);
        autoPounder.grantRole(autoPounder.COMPOUNDER_ROLE(), compounder);

        // In production: setClaimer(address(autoPounder)) must be called
        // on each staking node by the DELEGATOR role holder.
        // For tests, we impersonate and set the claimer.
        _setClaimerForAllNodes();
    }

    function _getStakingNodes() internal view returns (address[] memory) {
        return ITokenStakingNodesManager(TOKEN_STAKING_NODES_MANAGER).getAllNodes();
    }

    function _setClaimerForAllNodes() internal {
        address[] memory nodes = _getStakingNodes();

        for (uint256 i = 0; i < nodes.length; i++) {
            // The setClaimer function requires onlyDelegator.
            // In the fork test, we impersonate the YN_DEV address.
            vm.prank(MainnetActors.YN_DEV);
            try ITokenStakingNode(nodes[i]).setClaimer(address(autoPounder)) {}
            catch {
                // If YN_DEV doesn't have the role, try ADMIN
                vm.prank(MainnetActors.ADMIN);
                ITokenStakingNode(nodes[i]).setClaimer(address(autoPounder));
            }
        }
    }
}
