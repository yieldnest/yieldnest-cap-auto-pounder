// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRedemptionAssetsVault {
    function deposit(uint256 amount, address asset) external;
}
