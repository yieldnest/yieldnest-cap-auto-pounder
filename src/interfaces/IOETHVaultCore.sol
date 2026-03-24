// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IOETHVaultCore {
    function mint(address _asset, uint256 _amount, uint256 _minimumOusdAmount) external;
    function isSupportedAsset(address _asset) external view returns (bool);
    function priceUnitMint(address _asset) external view returns (uint256);
}
