// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IL2GatewayRouter
/// @notice Subset of the Arbitrum L2 Gateway Router used by ArbEthERC20BridgeSteward.
interface IL2GatewayRouter {
    /// @notice Initiates a token withdrawal from L2 to L1
    /// @param _l1Token Address of the L1 token
    /// @param _to Recipient address on L1
    /// @param _amount Amount of tokens to withdraw
    /// @param _data Extra data forwarded to the gateway
    function outboundTransfer(
        address _l1Token,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) external payable returns (bytes memory);

    /// @notice Returns the L2 gateway that handles a given L1 token
    function getGateway(address _token) external view returns (address gateway);

    /// @notice Returns the L2 token address that corresponds to a given L1 token
    function calculateL2TokenAddress(address _l1ERC20) external view returns (address);
}
