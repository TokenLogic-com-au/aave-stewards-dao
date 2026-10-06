// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {OracleMath} from "src/finance/libraries/OracleMath.sol";

contract MockAggregator {
  int256 public latestAnswer;
  uint8 public constant decimals = 8;

  constructor(int256 answer_) {
    latestAnswer = answer_;
  }
}

contract MockToken {
  uint8 public decimals;

  constructor(uint8 decimals_) {
    decimals = decimals_;
  }
}

contract OracleMathHarness {
  function getExpectedOut(address fromToken, address toToken, address fromOracle, address toOracle, uint256 amount)
    external
    view
    returns (uint256)
  {
    return OracleMath.getExpectedOut(fromToken, toToken, fromOracle, toOracle, amount);
  }
}

contract OracleMathTest is Test {
  uint8 internal constant MAX_FUZZ_DECIMALS = 18;
  uint256 internal constant MAX_FUZZ_AMOUNT = 1e30;
  uint256 internal constant MAX_FUZZ_PRICE = 1e12;
  uint256 internal constant OVERFLOW_AMOUNT = 1e60;

  OracleMathHarness internal harness;

  function setUp() public {
    harness = new OracleMathHarness();
  }

  function _token(uint8 decimals) internal returns (address) {
    return address(new MockToken(decimals));
  }

  function _oracle(int256 answer) internal returns (address) {
    return address(new MockAggregator(answer));
  }

  function test_getExpectedOut_18To6Decimals() public {
    uint256 out = harness.getExpectedOut(_token(18), _token(6), _oracle(100e8), _oracle(1e8), 1e18);
    assertEq(out, 100e6);
  }

  function test_getExpectedOut_6To18Decimals() public {
    uint256 out = harness.getExpectedOut(_token(6), _token(18), _oracle(1e8), _oracle(2000e8), 2000e6);
    assertEq(out, 1e18);
  }

  function test_getExpectedOut_roundsDown() public {
    uint256 out = harness.getExpectedOut(_token(18), _token(6), _oracle(1e8), _oracle(3e8), 1e18);
    assertEq(out, 333_333);
  }

  function test_getExpectedOut_zeroAmount() public {
    uint256 out = harness.getExpectedOut(_token(18), _token(6), _oracle(100e8), _oracle(1e8), 0);
    assertEq(out, 0);
  }

  function test_getExpectedOut_overflowSafe() public {
    uint256 out = harness.getExpectedOut(_token(18), _token(18), _oracle(2000e8), _oracle(1e8), OVERFLOW_AMOUNT);
    assertEq(out, 2000e60);
  }

  function test_getExpectedOut_revertsWith_InvalidPrice_fromOracleZero() public {
    address fromToken = _token(18);
    address toToken = _token(6);
    address fromOracle = _oracle(0);
    address toOracle = _oracle(1e8);
    vm.expectRevert(abi.encodeWithSelector(OracleMath.InvalidPrice.selector, fromOracle));
    harness.getExpectedOut(fromToken, toToken, fromOracle, toOracle, 1e18);
  }

  function test_getExpectedOut_revertsWith_InvalidPrice_fromOracleNegative() public {
    address fromToken = _token(18);
    address toToken = _token(6);
    address fromOracle = _oracle(-1);
    address toOracle = _oracle(1e8);
    vm.expectRevert(abi.encodeWithSelector(OracleMath.InvalidPrice.selector, fromOracle));
    harness.getExpectedOut(fromToken, toToken, fromOracle, toOracle, 1e18);
  }

  function test_getExpectedOut_revertsWith_InvalidPrice_toOracleZero() public {
    address fromToken = _token(18);
    address toToken = _token(6);
    address fromOracle = _oracle(1e8);
    address toOracle = _oracle(0);
    vm.expectRevert(abi.encodeWithSelector(OracleMath.InvalidPrice.selector, toOracle));
    harness.getExpectedOut(fromToken, toToken, fromOracle, toOracle, 1e18);
  }

  function test_getExpectedOut_revertsWith_InvalidPrice_toOracleNegative() public {
    address fromToken = _token(18);
    address toToken = _token(6);
    address fromOracle = _oracle(1e8);
    address toOracle = _oracle(-1);
    vm.expectRevert(abi.encodeWithSelector(OracleMath.InvalidPrice.selector, toOracle));
    harness.getExpectedOut(fromToken, toToken, fromOracle, toOracle, 1e18);
  }

  function test_fuzz_getExpectedOut_exactFloor(
    uint256 amount,
    uint256 priceFrom,
    uint256 priceTo,
    uint8 fromDecimals,
    uint8 toDecimals
  ) public {
    amount = bound(amount, 0, MAX_FUZZ_AMOUNT);
    priceFrom = bound(priceFrom, 1, MAX_FUZZ_PRICE);
    priceTo = bound(priceTo, 1, MAX_FUZZ_PRICE);
    fromDecimals = uint8(bound(fromDecimals, 0, MAX_FUZZ_DECIMALS));
    toDecimals = uint8(bound(toDecimals, 0, MAX_FUZZ_DECIMALS));

    uint256 out = harness.getExpectedOut(
      _token(fromDecimals), _token(toDecimals), _oracle(int256(priceFrom)), _oracle(int256(priceTo)), amount
    );

    uint256 expected = (amount * priceFrom * 10 ** toDecimals) / (priceTo * 10 ** fromDecimals);
    assertEq(out, expected);
  }
}
