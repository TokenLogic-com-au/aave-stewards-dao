// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBridgeSteward} from "../../IBridgeSteward.sol";

/// @title IOpEthERC20BridgeSteward
/// @author efecarranza.eth (TokenLogic)
/// @notice Defines the behaviour of the OpEthERC20BridgeSteward.
///         Adapted from IAaveOpEthERC20Bridge to include Steward Role.
interface IOpEthERC20BridgeSteward is IBridgeSteward {
    /// @dev `l1Token` does not match the canonical mapping for `l2Token`
    error InvalidL1Token();

    /// @dev Provided address cannot be the zero-address
    error InvalidZeroAddress();

    /// @dev Amount must be greater than zero
    error InvalidZeroAmount();

    /// @dev Token mapping already exists; remove it before setting a new one
    error TokenAlreadySet();

    /// @dev Token has no L1 mapping set — call `setTokenMapping` first
    error TokenNotSet();

    /// @notice Emitted when bridging an ERC20 token from Optimism to Mainnet
    /// @param token Address of the OP token
    /// @param l1token Address of the equivalent Mainnet token
    /// @param amount Amount of tokens bridged
    /// @param to Address receiving token on Mainnet
    event Bridge(
        address indexed token,
        address indexed l1token,
        uint256 amount,
        address indexed to
    );

    /// @notice Emitted when bridging native ETH from Optimism to Mainnet
    /// @param amount Amount of ETH bridged
    /// @param to Address receiving the ETH on Mainnet
    event BridgeEth(uint256 amount, address indexed to);

    /// @notice Emitted when a token mapping (L2 -> L1) is updated
    /// @param l2Token Address of the token on Optimism
    /// @param l1Token Address of the corresponding token on Mainnet
    event TokenMappingUpdated(address indexed l2Token, address l1Token);

    /// @notice Emitted when a token mapping is removed
    /// @param l2Token Address of the token on Optimism that was removed
    event TokenMappingRemoved(address indexed l2Token);

    /// @notice Bridges native ETH sent along with the call to the Mainnet Collector via
    ///         the OP Stack native ETH path (`L2StandardBridge.bridgeETHTo`).
    function bridgeEth() external payable;

    /// @notice Sets a token mapping for bridging (L2 -> L1)
    /// @param l2Token Address of the token on Optimism
    /// @param l1Token Address of the corresponding token on Mainnet
    function setTokenMapping(address l2Token, address l1Token) external;

    /// @notice Removes a token mapping
    /// @param l2Token Address of the token on Optimism
    function removeTokenMapping(address l2Token) external;

    /// @notice Returns the Optimism Standard Bridge address
    function L2_STANDARD_BRIDGE() external view returns (address);

    /// @notice Returns the minimum gas limit for bridge operations
    function MIN_GAS_LIMIT() external view returns (uint32);

    /// @notice Returns the L1 token address mapped to an L2 token
    /// @param l2Token Address of the token on Optimism
    /// @return l1Token Address of the corresponding token on Mainnet
    function tokenMapping(
        address l2Token
    ) external view returns (address l1Token);
}
