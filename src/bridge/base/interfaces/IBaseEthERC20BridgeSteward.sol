// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBridgeSteward} from "../../IBridgeSteward.sol";

/// @title IBaseEthERC20BridgeSteward
/// @author efecarranza.eth (TokenLogic)
/// @notice Defines the behaviour of the BaseEthERC20BridgeSteward.
interface IBaseEthERC20BridgeSteward is IBridgeSteward {
  /// @notice Emitted when bridging an ERC20 token from Base to Mainnet
  /// @param token Address of the Base token
  /// @param l1Token Address of the equivalent Mainnet token
  /// @param amount Amount of tokens bridged
  /// @param to Address receiving the token on Mainnet
  event Bridge(address indexed token, address indexed l1Token, uint256 amount, address indexed to);

  /// @notice Emitted when a token mapping (L2 -> L1) is updated
  /// @param l2Token Address of the token on Base
  /// @param l1Token Address of the corresponding token on Mainnet
  event TokenMappingUpdated(address indexed l2Token, address l1Token);

  /// @notice Emitted when a token mapping is removed
  /// @param l2Token Address of the token on Base that was removed
  event RemovedTokenMapping(address indexed l2Token);

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

  /// @notice Sets a token mapping for bridging (L2 -> L1)
  /// @param l2Token Address of the token on Base
  /// @param l1Token Address of the corresponding token on Mainnet
  function setTokenMapping(address l2Token, address l1Token) external;

  /// @notice Removes a token mapping
  /// @param l2Token Address of the token on Base
  function removeTokenMapping(address l2Token) external;

  /// @notice Returns the Base L2 Standard Bridge address
  function L2_STANDARD_BRIDGE() external view returns (address);

  /// @notice Returns the minimum gas limit for bridge operations
  function MIN_GAS_LIMIT() external view returns (uint32);

  /// @notice Returns the L1 token configured for `l2Token`
  /// @param l2Token Address of the token on Base
  /// @return l1Token Address of the corresponding token on Mainnet
  function tokenMapping(address l2Token) external view returns (address l1Token);
}
