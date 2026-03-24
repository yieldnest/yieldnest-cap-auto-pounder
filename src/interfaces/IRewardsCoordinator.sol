// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewardsCoordinator {
    struct TokenTreeMerkleLeaf {
        IERC20 token;
        uint256 cumulativeEarnings;
    }

    struct EarnerTreeMerkleLeaf {
        address earner;
        bytes32 earnerTokenRoot;
    }

    struct RewardsMerkleClaim {
        uint32 rootIndex;
        uint32 earnerIndex;
        bytes earnerTreeProof;
        EarnerTreeMerkleLeaf earnerLeaf;
        uint32[] tokenIndices;
        bytes[] tokenTreeProofs;
        TokenTreeMerkleLeaf[] tokenLeaves;
    }

    function processClaim(RewardsMerkleClaim calldata claim, address recipient) external;
    function setClaimerFor(address claimer) external;
    function claimerFor(address earner) external view returns (address);
    function cumulativeClaimed(address earner, IERC20 token) external view returns (uint256);
}
