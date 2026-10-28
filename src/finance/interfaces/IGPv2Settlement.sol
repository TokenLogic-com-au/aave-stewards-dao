// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IGPv2AllowListAuthentication} from "./IGPv2AllowListAuthentication.sol";

/// @title Gnosis Protocol v2 Settlement Interface
/// @author Gnosis Developers
/// @dev Vendored from `cowprotocol/contracts` at commit `a10f40788af29467e87de3dbf2196662b0a6b500`, path
///      `src/contracts/GPv2Settlement.sol`, reduced to the functions this repo uses.
interface IGPv2Settlement {
  /// @dev https://github.com/cowprotocol/contracts/blob/a10f40788af29467e87de3dbf2196662b0a6b500/src/contracts/libraries/GPv2Trade.sol
  struct Trade {
    uint256 sellTokenIndex;
    uint256 buyTokenIndex;
    address receiver;
    uint256 sellAmount;
    uint256 buyAmount;
    uint32 validTo;
    bytes32 appData;
    uint256 feeAmount;
    uint256 flags;
    uint256 executedAmount;
    bytes signature;
  }

  /// @dev https://github.com/cowprotocol/contracts/blob/a10f40788af29467e87de3dbf2196662b0a6b500/src/contracts/libraries/GPv2Interaction.sol
  struct Interaction {
    address target;
    uint256 value;
    bytes callData;
  }

  function authenticator() external view returns (IGPv2AllowListAuthentication);

  function vaultRelayer() external view returns (address);

  function domainSeparator() external view returns (bytes32);

  function filledAmount(bytes calldata orderUid) external view returns (uint256);

  function settle(
    IERC20[] calldata tokens,
    uint256[] calldata clearingPrices,
    Trade[] calldata trades,
    Interaction[][3] calldata interactions
  ) external;
}
