// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {CAPAutoPounder} from "../src/CAPAutoPounder.sol";
import {MainnetContracts} from "./Contracts.sol";
import {MainnetActors} from "./Actors.sol";

contract Deploy is Script {
    function run() external {
        // Build reward tokens array (EIGEN, WETH, USDC, ARPA)
        address[] memory rewardTokens = new address[](4);
        rewardTokens[0] = MainnetContracts.EIGEN;
        rewardTokens[1] = MainnetContracts.WETH;
        rewardTokens[2] = MainnetContracts.USDC;
        rewardTokens[3] = MainnetContracts.ARPA;

        // Fee tiers for Uniswap V3 swaps to WETH
        uint24[] memory fees = new uint24[](4);
        fees[0] = MainnetContracts.FEE_MEDIUM; // EIGEN/WETH 0.3%
        fees[1] = 0; // WETH — no swap needed
        fees[2] = MainnetContracts.FEE_LOW; // USDC/WETH 0.05%
        fees[3] = MainnetContracts.FEE_HIGH; // ARPA/WETH 1%

        CAPAutoPounder.Config memory config = CAPAutoPounder.Config({
            rewardsCoordinator: MainnetContracts.REWARDS_COORDINATOR,
            capInterestContract: MainnetContracts.CAP_INTEREST_CONTRACT,
            capRestaker: MainnetContracts.CAP_RESTAKER_SAFE,
            capInterestToken: MainnetContracts.USDC,
            swapRouter: MainnetContracts.UNISWAP_V3_ROUTER,
            weth: MainnetContracts.WETH,
            oeth: MainnetContracts.OETH,
            woeth: MainnetContracts.WOETH,
            oethVault: MainnetContracts.OETH_VAULT,
            redemptionAssetsVault: MainnetContracts.REDEMPTION_ASSETS_VAULT,
            rewardTokens: rewardTokens,
            swapPoolFees: fees
        });

        address admin = MainnetActors.ADMIN; // YnSecurityCouncil multisig

        console.log("Deploying CAPAutoPounder...");
        console.log("Admin (YnSecurityCouncil):", admin);
        console.log("RewardsCoordinator:", MainnetContracts.REWARDS_COORDINATOR);
        console.log("SwapRouter:", MainnetContracts.UNISWAP_V3_ROUTER);
        console.log("RedemptionAssetsVault:", MainnetContracts.REDEMPTION_ASSETS_VAULT);
        console.log("Reward tokens:", rewardTokens.length);

        vm.startBroadcast();

        CAPAutoPounder autoPounder = new CAPAutoPounder(config, admin);

        vm.stopBroadcast();

        console.log("CAPAutoPounder deployed at:", address(autoPounder));
        console.log("");
        console.log("Post-deployment steps:");
        console.log("  1. Run Verify.s.sol to validate config");
        console.log("  2. setClaimer(autoPounder) on all staking nodes via YnDelegator Safe tx");
        console.log("  3. grantRole(COMPOUNDER_ROLE, keeperWallet) via admin multisig");
    }
}
