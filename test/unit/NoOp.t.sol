// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

contract NoOp is Test {
    function test_NoOp() public pure {
        assert(true);
    }
}
