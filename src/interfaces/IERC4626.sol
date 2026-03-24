// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC4626 {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function asset() external view returns (address);
    function previewDeposit(uint256 assets) external view returns (uint256 shares);
    function totalAssets() external view returns (uint256);
}
