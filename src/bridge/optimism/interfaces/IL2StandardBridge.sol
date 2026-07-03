// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IL2StandardBridge
/// @notice Interface for the Optimism L2 Standard Bridge
interface IL2StandardBridge {
    /// @notice Bridges ERC20 tokens from L2 to a specified address on L1
    /// @param l2Token Address of the L2 token
    /// @param l1Token Address of the corresponding L1 token
    /// @param to Address to receive the tokens on L1
    /// @param amount Amount of tokens to bridge
    /// @param minGasLimit Minimum gas limit for the L1 execution
    /// @param extraData Extra data to include in the bridge message
    function bridgeERC20To(
        address l2Token,
        address l1Token,
        address to,
        uint256 amount,
        uint32 minGasLimit,
        bytes calldata extraData
    ) external;

    /// @notice Bridges native ETH from L2 to a specified address on L1
    /// @param to Address to receive the ETH on L1
    /// @param minGasLimit Minimum gas limit for the L1 execution
    /// @param extraData Extra data to include in the bridge message
    function bridgeETHTo(
        address to,
        uint32 minGasLimit,
        bytes calldata extraData
    ) external payable;
}
