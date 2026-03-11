// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {CAPAutoPounder} from "../src/CAPAutoPounder.sol";
import {MainnetContracts} from "./Contracts.sol";
import {MainnetActors} from "./Actors.sol";
import {IRewardsCoordinator} from "../src/interfaces/IRewardsCoordinator.sol";

interface ITokenStakingNodesManager {
    function getAllNodes() external view returns (address[] memory);
}

contract Verify is Script {
    function run() external view {
        address autoPounderAddr = vm.envAddress("AUTO_POUNDER_ADDRESS");
        CAPAutoPounder autoPounder = CAPAutoPounder(autoPounderAddr);

        console.log("Verifying CAPAutoPounder at:", autoPounderAddr);
        console.log("========================================");

        // --- Config verification ---
        uint256 failures = 0;

        failures += _check(
            "rewardsCoordinator", address(autoPounder.rewardsCoordinator()), MainnetContracts.REWARDS_COORDINATOR
        );
        failures += _check("swapRouter", address(autoPounder.swapRouter()), MainnetContracts.UNISWAP_V3_ROUTER);
        failures += _check("weth", autoPounder.weth(), MainnetContracts.WETH);
        failures += _check("oeth", autoPounder.oeth(), MainnetContracts.OETH);
        failures += _check("woeth", address(autoPounder.woeth()), MainnetContracts.WOETH);
        failures += _check("oethVault", address(autoPounder.oethVault()), MainnetContracts.OETH_VAULT);
        failures += _check(
            "redemptionAssetsVault",
            address(autoPounder.redemptionAssetsVault()),
            MainnetContracts.REDEMPTION_ASSETS_VAULT
        );
        failures += _check(
            "capInterestContract", address(autoPounder.capInterestContract()), MainnetContracts.CAP_INTEREST_CONTRACT
        );
        failures += _check("capRestaker", autoPounder.capRestaker(), MainnetContracts.CAP_RESTAKER_SAFE);
        failures += _check("capInterestToken", autoPounder.capInterestToken(), MainnetContracts.USDC);

        // --- Reward tokens ---
        uint256 tokenCount = autoPounder.getRewardTokenCount();
        console.log("");
        console.log("Reward tokens:", tokenCount);
        if (tokenCount != 4) {
            console.log("  FAIL: expected 4 reward tokens, got", tokenCount);
            failures++;
        }

        address[] memory tokens = autoPounder.getRewardTokens();
        if (tokenCount >= 4) {
            failures += _check("rewardTokens[0] (EIGEN)", tokens[0], MainnetContracts.EIGEN);
            failures += _check("rewardTokens[1] (WETH)", tokens[1], MainnetContracts.WETH);
            failures += _check("rewardTokens[2] (USDC)", tokens[2], MainnetContracts.USDC);
            failures += _check("rewardTokens[3] (ARPA)", tokens[3], MainnetContracts.ARPA);
        }

        // --- Roles ---
        console.log("");
        bytes32 adminRole = autoPounder.DEFAULT_ADMIN_ROLE();
        bool adminHasRole = autoPounder.hasRole(adminRole, MainnetActors.ADMIN);
        if (adminHasRole) {
            console.log("  OK: YnSecurityCouncil has DEFAULT_ADMIN_ROLE");
        } else {
            console.log("  FAIL: YnSecurityCouncil missing DEFAULT_ADMIN_ROLE");
            failures++;
        }

        // --- Claimer check (only if setClaimer has been called) ---
        console.log("");
        console.log("Claimer status (staking nodes):");
        IRewardsCoordinator rc = IRewardsCoordinator(MainnetContracts.REWARDS_COORDINATOR);
        address[] memory nodes = ITokenStakingNodesManager(MainnetContracts.TOKEN_STAKING_NODES_MANAGER).getAllNodes();

        for (uint256 i = 0; i < nodes.length; i++) {
            address claimer = rc.claimerFor(nodes[i]);
            if (claimer == autoPounderAddr) {
                console.log("  OK: node", i, "claimer is autoPounder");
            } else {
                console.log("  PENDING: node", i, "claimer is", claimer);
                console.log("           (needs setClaimer via YnDelegator Safe tx)");
            }
        }

        // --- Summary ---
        console.log("");
        console.log("========================================");
        if (failures == 0) {
            console.log("ALL CHECKS PASSED");
        } else {
            console.log("FAILURES:", failures);
        }
    }

    function _check(
        string memory,
        /* name */
        address actual,
        address expected
    )
        internal
        pure
        returns (uint256)
    {
        if (actual == expected) {
            return 0;
        } else {
            return 1;
        }
    }
}
