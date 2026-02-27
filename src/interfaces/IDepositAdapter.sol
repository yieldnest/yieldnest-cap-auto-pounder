// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDepositAdapter {
    function deposit(address asset, uint256 amount, address receiver) external returns (uint256 shares);
}
