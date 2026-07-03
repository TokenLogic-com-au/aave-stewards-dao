// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IArbSys
/// @notice Arbitrum system precompile (0x0000...0064).
interface IArbSys {
    /// @notice Initiates a native ETH withdrawal from L2 to `destination` on L1
    /// @param destination L1 address that will receive the ETH
    /// @return uniqueId Sequence number for the L2-to-L1 message
    function withdrawEth(address destination) external payable returns (uint256 uniqueId);
}
