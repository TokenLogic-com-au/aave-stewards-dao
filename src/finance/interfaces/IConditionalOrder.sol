// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {GPv2Order} from "src/finance/libraries/GPv2Order.sol";

/**
 * @title Conditional Order Interface
 * @author CoW Protocol Developers + mfw78 <mfw78@rndlabs.xyz>
 * @dev Vendored from `cowprotocol/composable-cow` at commit `c0435953ac8312a606d66c91554f2bb4d22ec686`, path `src/interfaces/IConditionalOrder.sol`,
 *      reduced to what this repo uses.
 */
interface IConditionalOrder {
  /// @dev This error is returned by the `getTradeableOrder` function if the order condition is not met.
  ///      A parameter of `string` type is included to allow the caller to specify the reason for the failure.
  error OrderNotValid(string);

  // Signal to a watch tower that polling should be attempted again.
  error PollTryNextBlock(string reason);
  // Signal to a watch tower that polling should be attempted again at a specific epoch (unix timestamp).
  error PollTryAtEpoch(uint256 timestamp, string reason);

  /**
   * @dev This struct is used to uniquely identify a conditional order for an owner.
   *      H(handler || salt || staticInput) **MUST** be unique for an owner.
   */
  struct ConditionalOrderParams {
    IConditionalOrder handler;
    bytes32 salt;
    bytes staticInput;
  }

  /**
   * Verify if a given discrete order is valid.
   * @dev Used in combination with `isValidSafeSignature` to verify that the order is signed by the Safe.
   *      **MUST** revert if the order condition is not met.
   * @dev The `order` parameter is ignored / not validated by the `IConditionalOrderGenerator` implementation.
   * @param owner the contract who is the owner of the order
   * @param sender the `msg.sender` of the transaction
   * @param _hash the hash of the order
   * @param domainSeparator the domain separator used to sign the order
   * @param ctx the context key of the order (bytes32(0) if a merkle tree is used, otherwise H(params))
   * @param staticInput the static input for all discrete orders cut from this conditional order
   * @param offchainInput dynamic off-chain input for a discrete order cut from this conditional order
   * @param order `GPv2Order.Data` of a discrete order to be verified (if *not* an `IConditionalOrderGenerator`).
   */
  function verify(
    address owner,
    address sender,
    bytes32 _hash,
    bytes32 domainSeparator,
    bytes32 ctx,
    bytes calldata staticInput,
    bytes calldata offchainInput,
    GPv2Order.Data calldata order
  ) external view;
}

/**
 * @title Conditional Order Generator Interface
 * @author mfw78 <mfw78@rndlabs.xyz>
 * @dev Vendored from `cowprotocol/composable-cow` at commit `c0435953ac8312a606d66c91554f2bb4d22ec686`, path `src/interfaces/IConditionalOrder.sol`,
 *      reduced to what this repo uses.
 */
interface IConditionalOrderGenerator is IConditionalOrder, IERC165 {
  /**
   * @dev Get a tradeable order that can be posted to the CoW Protocol API and would pass signature validation.
   *      **MUST** revert if the order condition is not met.
   * @param owner the contract who is the owner of the order
   * @param sender the `msg.sender` of the parent `isValidSignature` call
   * @param ctx the context of the order (bytes32(0) if merkle tree is used, otherwise the H(params))
   * @param staticInput the static input for all discrete orders cut from this conditional order
   * @param offchainInput dynamic off-chain input for a discrete order cut from this conditional order
   * @return the tradeable order for submission to the CoW Protocol API
   */
  function getTradeableOrder(
    address owner,
    address sender,
    bytes32 ctx,
    bytes calldata staticInput,
    bytes calldata offchainInput
  ) external view returns (GPv2Order.Data memory);
}
