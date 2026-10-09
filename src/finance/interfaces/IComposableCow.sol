// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
// Interface extracted from https://github.com/cowprotocol/composable-cow/blob/c0435953ac8312a606d66c91554f2bb4d22ec686/src/ComposableCoW.sol
// composable-cow tag ack3-rev2.0 (file last changed in 9f0c6110ec2eb498341a0d45a0168e735a18ed1b).
// Subset of the external API: PayloadStruct, singleOrders, domainSeparator, create, remove, hash, isValidSafeSignature.

import {IConditionalOrder} from "composable-cow/interfaces/IConditionalOrder.sol";

interface IComposableCow {
  /// A struct to encapsulate order parameters / offchain input
  struct PayloadStruct {
    bytes32[] proof;
    IConditionalOrder.ConditionalOrderParams params;
    bytes offchainInput;
  }

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
}
