// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockAggregator {
  int256 public latestAnswer;
  uint8 public constant decimals = 8;

  constructor(int256 answer_) {
    latestAnswer = answer_;
  }
}
