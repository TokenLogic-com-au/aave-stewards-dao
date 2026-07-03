// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

/// @title IOptimismMintableERC20
/// @notice Optimism Standard Bridge interface for L2-mintable tokens.
interface IOptimismMintableERC20 is IERC165 {
    function remoteToken() external view returns (address);
    function bridge() external returns (address);
    function mint(address _to, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;
}
