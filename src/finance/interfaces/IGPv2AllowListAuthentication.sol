// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

/// @title Gnosis Protocol v2 AllowList Authentication Interface
/// @author Gnosis Developers
/// @dev Vendored from `cowprotocol/contracts` at commit `a10f40788af29467e87de3dbf2196662b0a6b500`, path
///      `src/contracts/GPv2AllowListAuthentication.sol`, reduced to the functions this repo uses.
interface IGPv2AllowListAuthentication {
  function manager() external view returns (address);

  function addSolver(address solver) external;
}
