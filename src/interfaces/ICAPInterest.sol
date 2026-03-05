// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICAPInterest {
    function realizeRestakerInterest(address restaker, address token) external;
}
