// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

function badAnswers() pure returns (int256[2] memory) {
  return [int256(0), int256(-1)];
}

contract MockAggregator {
  int256 public latestAnswer;
  uint8 public constant decimals = 8;

  constructor(int256 answer_) {
    latestAnswer = answer_;
  }
}
