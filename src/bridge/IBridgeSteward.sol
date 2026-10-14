// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IBridgeSteward
/// @author efecarranza.eth (TokenLogic)
/// @notice Common interface implemented by all bridge stewards so AIPs can
///         interact with them uniformly across networks.
interface IBridgeSteward {
    /// @notice Bridges an ERC20 token from the local Collector to the Mainnet Collector
    /// @param token Address of the token on the local network
    /// @param amount Amount of tokens to bridge
    function bridge(address token, uint256 amount) external;

    /// @notice Rescues stuck ERC20 tokens back to the local Collector
    /// @param token Address of the ERC20 token to rescue
    function rescueToken(address token) external;

    /// @notice Rescues stuck ETH back to the local Collector
    function rescueEth() external;
}
