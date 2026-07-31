// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

/// @title ILegacyMintableERC20
/// @notice Legacy OP Stack Standard Bridge interface for L2-mintable tokens.
interface ILegacyMintableERC20 is IERC165 {
  function l1Token() external view returns (address);
  function mint(address _to, uint256 _amount) external;
  function burn(address _from, uint256 _amount) external;
}
