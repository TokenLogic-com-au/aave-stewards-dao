// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GPv2Order} from "src/finance/libraries/GPv2Order.sol";
import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {IConditionalOrder, IConditionalOrderGenerator} from "src/finance/interfaces/IConditionalOrder.sol";

/// @dev This error is returned by the `verify` function if the *generated* order hash does not match
///      the hash passed as a parameter.
string constant INVALID_HASH = "invalid hash";

/**
 * @title Base logic for conditional orders.
 * @dev Enforces the order verification logic for conditional orders, allowing developers
 *      to focus on the logic for generating the tradeable order.
 *      Vendored from `cowprotocol/composable-cow` at commit `c0435953ac8312a606d66c91554f2bb4d22ec686`, path `src/BaseConditionalOrder.sol`,
 *      reduced to what this repo uses.
 * @author mfw78 <mfw78@rndlabs.xyz>
 */
abstract contract BaseConditionalOrder is IConditionalOrderGenerator {
  /**
   * @inheritdoc IConditionalOrder
   * @dev As an order generator, the `GPv2Order.Data` passed as a parameter is ignored / not validated.
   */
  function verify(
    address owner,
    address sender,
    bytes32 _hash,
    bytes32 domainSeparator,
    bytes32 ctx,
    bytes calldata staticInput,
    bytes calldata offchainInput,
    GPv2Order.Data calldata
  ) external view override {
    GPv2Order.Data memory generatedOrder = getTradeableOrder(owner, sender, ctx, staticInput, offchainInput);

    /// @dev Verify that the *generated* order is valid and matches the payload.
    if (!(_hash == GPv2Order.hash(generatedOrder, domainSeparator))) {
      revert IConditionalOrder.OrderNotValid(INVALID_HASH);
    }
  }

  /**
   * @dev Set the visibility of this function to `public` to allow `verify` to call it.
   * @inheritdoc IConditionalOrderGenerator
   */
  function getTradeableOrder(
    address owner,
    address sender,
    bytes32 ctx,
    bytes calldata staticInput,
    bytes calldata offchainInput
  ) public view virtual override returns (GPv2Order.Data memory);

  /**
   * @inheritdoc IERC165
   */
  function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
    return interfaceId == type(IConditionalOrderGenerator).interfaceId || interfaceId == type(IERC165).interfaceId;
  }
}
