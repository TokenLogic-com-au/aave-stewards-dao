// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title Gnosis Protocol v2 Order Library
/// @author Gnosis Developers
/// @dev Vendored from `cowprotocol/contracts` at commit `a10f40788af29467e87de3dbf2196662b0a6b500`, path
///      `src/contracts/libraries/GPv2Order.sol`, reduced to what this repo uses.
library GPv2Order {
  /// @dev The complete data for a Gnosis Protocol order. This struct contains
  /// all order parameters that are signed for submitting to GP.
  struct Data {
    IERC20 sellToken;
    IERC20 buyToken;
    address receiver;
    uint256 sellAmount;
    uint256 buyAmount;
    uint32 validTo;
    bytes32 appData;
    uint256 feeAmount;
    bytes32 kind;
    bool partiallyFillable;
    bytes32 sellTokenBalance;
    bytes32 buyTokenBalance;
  }

  /// @dev The marker value for a sell order for computing the order struct hash, `keccak256("sell")`.
  bytes32 internal constant KIND_SELL = hex"f3b277728b3fee749481eb3e0b3b48980dbbab78658fc419025cb16eee346775";

  /// @dev The TokenBalance marker value for using direct ERC20 balances, `keccak256("erc20")`.
  bytes32 internal constant BALANCE_ERC20 = hex"5a28e9363bb942b639270062aa6bb295f434bcdfc42c97267bf003f272060dc9";

  /// ```
  /// keccak256(
  ///     "Order(" +
  ///         "address sellToken," +
  ///         "address buyToken," +
  ///         "address receiver," +
  ///         "uint256 sellAmount," +
  ///         "uint256 buyAmount," +
  ///         "uint32 validTo," +
  ///         "bytes32 appData," +
  ///         "uint256 feeAmount," +
  ///         "string kind," +
  ///         "bool partiallyFillable," +
  ///         "string sellTokenBalance," +
  ///         "string buyTokenBalance" +
  ///     ")"
  /// )
  /// ```
  bytes32 internal constant TYPE_HASH = hex"d5a25ba2e97094ad7d83dc28a6572da797d6b3e7fc6663bd93efb789fc17e489";

  /// @dev Return the EIP-712 signing hash for the specified order.
  ///
  /// @param order The order to compute the EIP-712 signing hash for.
  /// @param domainSeparator The EIP-712 domain separator to use.
  /// @return orderDigest The 32 byte EIP-712 struct hash.
  function hash(Data memory order, bytes32 domainSeparator) internal pure returns (bytes32 orderDigest) {
    bytes32 structHash;

    // NOTE: Compute the EIP-712 order struct hash in place. As suggested
    // in the EIP proposal, noting that the order struct has 12 fields, and
    // prefixing the type hash `(1 + 12) * 32 = 416` bytes to hash.
    // <https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md#rationale-for-encodedata>
    // solhint-disable-next-line no-inline-assembly
    assembly {
      let dataStart := sub(order, 32)
      let temp := mload(dataStart)
      mstore(dataStart, TYPE_HASH)
      structHash := keccak256(dataStart, 416)
      mstore(dataStart, temp)
    }

    // NOTE: Now that we have the struct hash, compute the EIP-712 signing
    // hash using scratch memory past the free memory pointer. The signing
    // hash is computed from `"\x19\x01" || domainSeparator || structHash`.
    // <https://docs.soliditylang.org/en/v0.7.6/internals/layout_in_memory.html#layout-in-memory>
    // <https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md#specification>
    // solhint-disable-next-line no-inline-assembly
    assembly {
      let freeMemoryPointer := mload(0x40)
      mstore(freeMemoryPointer, "\x19\x01")
      mstore(add(freeMemoryPointer, 2), domainSeparator)
      mstore(add(freeMemoryPointer, 34), structHash)
      orderDigest := keccak256(freeMemoryPointer, 66)
    }
  }
}
