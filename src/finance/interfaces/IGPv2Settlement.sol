// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

interface IGPv2Settlement {
  function domainSeparator() external view returns (bytes32);
}
