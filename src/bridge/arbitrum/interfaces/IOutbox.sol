// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IOutbox
/// @notice Arbitrum L1 Outbox used to finalize L2-to-L1 messages.
interface IOutbox {
    /// @notice Executes an L2-to-L1 message after its challenge period has elapsed
    /// @param proof Merkle proof of the message inclusion in the L2 outbox
    /// @param index Index of the message in the outbox
    /// @param l2Sender L2 address that initiated the message
    /// @param to L1 target address of the message
    /// @param l2Block L2 block at which the message was emitted
    /// @param l1Block L1 block at which the message was emitted
    /// @param l2Timestamp L2 timestamp at which the message was emitted
    /// @param value ETH value forwarded with the message
    /// @param data Calldata to forward to `to`
    function executeTransaction(
        bytes32[] calldata proof,
        uint256 index,
        address l2Sender,
        address to,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        uint256 value,
        bytes calldata data
    ) external;
}
