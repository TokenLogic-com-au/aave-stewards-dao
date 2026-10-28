// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IConditionalOrder} from "./IConditionalOrder.sol";
import {GPv2Order} from "../libraries/GPv2Order.sol";

interface IComposableCow {
  /// A struct to encapsulate order parameters / offchain input
  struct PayloadStruct {
    bytes32[] proof;
    IConditionalOrder.ConditionalOrderParams params;
    bytes offchainInput;
  }

  /// @dev Vendored from `cowprotocol/composable-cow` at commit `c0435953ac8312a606d66c91554f2bb4d22ec686`, path `src/ComposableCoW.sol`.
  error SingleOrderNotAuthed();

  /// @dev Vendored from `cowprotocol/composable-cow` at commit `c0435953ac8312a606d66c91554f2bb4d22ec686`, path `src/ComposableCoW.sol`.
  event ConditionalOrderCreated(address indexed owner, IConditionalOrder.ConditionalOrderParams params);

  /// @dev Mapping of owner's single orders
  function singleOrders(address user, bytes32 _hash) external returns (bool);

  /// @dev Domain separator is only used for generating signatures
  function domainSeparator() external view returns (bytes32);

  /// Authorise a single conditional order
  /// @param params The parameters of the conditional order
  /// @param dispatch Whether to dispatch the `ConditionalOrderCreated` event
  function create(IConditionalOrder.ConditionalOrderParams calldata params, bool dispatch) external;

  /// Remove the authorisation of a single conditional order
  /// @param singleOrderHash The hash of the single conditional order to remove
  function remove(bytes32 singleOrderHash) external;

  /// Return the hash of the conditional order parameters
  /// @param params `ConditionalOrderParams` for the order
  /// @return hash of the conditional order parameters
  function hash(IConditionalOrder.ConditionalOrderParams memory params) external pure returns (bytes32);

  /// @dev This function does not make use of the `typeHash` parameter as CoW Protocol does not
  ///      have more than one type.
  /// @param encodeData Is the abi encoded `GPv2Order.Data`
  /// @param payload Is the abi encoded `PayloadStruct`
  function isValidSafeSignature(
    address safe,
    address sender,
    bytes32 _hash,
    bytes32 _domainSeparator,
    bytes32, // typeHash
    bytes calldata encodeData,
    bytes calldata payload
  ) external view returns (bytes4 magic);

  /// @dev Vendored from `cowprotocol/composable-cow` at commit `c0435953ac8312a606d66c91554f2bb4d22ec686`, path `src/ComposableCoW.sol`.
  function getTradeableOrderWithSignature(
    address owner,
    IConditionalOrder.ConditionalOrderParams calldata params,
    bytes calldata offchainInput,
    bytes32[] calldata proof
  ) external view returns (GPv2Order.Data memory order, bytes memory signature);
}
