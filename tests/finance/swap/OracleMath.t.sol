// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {OracleMath} from "src/finance/swap/libraries/OracleMath.sol";
import {MockAggregator} from "tests/finance/swap/OracleMocks.sol";

contract OracleMathHarness {
  function getExpectedOut(address fromToken, address toToken, address fromOracle, address toOracle, uint256 amount)
    external
    view
    returns (uint256)
  {
    return OracleMath.getExpectedOut(fromToken, toToken, fromOracle, toOracle, amount);
  }

  function getMinOut(
    address fromToken,
    address toToken,
    address fromOracle,
    address toOracle,
    uint256 amount,
    uint256 slippage
  ) external view returns (uint256) {
    return OracleMath.getMinOut(fromToken, toToken, fromOracle, toOracle, amount, slippage);
  }
}

contract OracleMathTest is Test {
  uint8 internal constant MAX_FUZZ_DECIMALS = 18;
  uint256 internal constant MAX_FUZZ_AMOUNT = 1e30;
  uint256 internal constant MAX_FUZZ_PRICE = 1e12;
  uint256 internal constant OVERFLOW_AMOUNT = 1e60;
  uint256 internal constant TEST_BPS = 10_000;

  OracleMathHarness internal harness;

  function setUp() public {
    harness = new OracleMathHarness();
  }

  function test_getExpectedOut_18To6Decimals() public {
    uint256 out =
      harness.getExpectedOut(_newMockToken(18), _newMockToken(6), _newMockOracle(100e8), _newMockOracle(1e8), 1e18);
    assertEq(out, 100e6);
  }

  function test_getExpectedOut_6To18Decimals() public {
    uint256 out =
      harness.getExpectedOut(_newMockToken(6), _newMockToken(18), _newMockOracle(1e8), _newMockOracle(2000e8), 2000e6);
    assertEq(out, 1e18);
  }

  function test_getExpectedOut_roundsDown() public {
    uint256 out =
      harness.getExpectedOut(_newMockToken(18), _newMockToken(6), _newMockOracle(1e8), _newMockOracle(3e8), 1e18);
    assertEq(out, 333_333);
  }

  function test_getExpectedOut_overflowSafe() public {
    uint256 out = harness.getExpectedOut(
      _newMockToken(18), _newMockToken(18), _newMockOracle(2000e8), _newMockOracle(1e8), OVERFLOW_AMOUNT
    );
    assertEq(out, 2000e60);
  }

  function test_getExpectedOut_revertsWith_InvalidPrice_fromOracleZeroOrNegative() public {
    address fromToken = _newMockToken(18);
    address toToken = _newMockToken(6);
    address toOracle = _newMockOracle(1e8);
    int256[2] memory badAnswers = [int256(0), int256(-1)];
    for (uint256 i; i < badAnswers.length; i++) {
      address fromOracle = _newMockOracle(badAnswers[i]);
      vm.expectRevert(abi.encodeWithSelector(OracleMath.InvalidPrice.selector, fromOracle));
      harness.getExpectedOut(fromToken, toToken, fromOracle, toOracle, 1e18);
    }
  }

  function test_getExpectedOut_revertsWith_InvalidPrice_toOracleZeroOrNegative() public {
    address fromToken = _newMockToken(18);
    address toToken = _newMockToken(6);
    address fromOracle = _newMockOracle(1e8);
    int256[2] memory badAnswers = [int256(0), int256(-1)];
    for (uint256 i; i < badAnswers.length; i++) {
      address toOracle = _newMockOracle(badAnswers[i]);
      vm.expectRevert(abi.encodeWithSelector(OracleMath.InvalidPrice.selector, toOracle));
      harness.getExpectedOut(fromToken, toToken, fromOracle, toOracle, 1e18);
    }
  }

  function test_getMinOut_50bps() public {
    uint256 out =
      harness.getMinOut(_newMockToken(18), _newMockToken(6), _newMockOracle(100e8), _newMockOracle(1e8), 1e18, 50);
    assertEq(out, 99_500_000);
  }

  function test_getMinOut_roundsDown() public {
    uint256 out =
      harness.getMinOut(_newMockToken(18), _newMockToken(6), _newMockOracle(1e8), _newMockOracle(3e8), 1e18, 49);
    assertEq(out, 331_699);
  }

  function test_fuzz_getMinOut_exactFloor(
    uint8 fromDecimals,
    uint8 toDecimals,
    uint256 priceFrom,
    uint256 priceTo,
    uint256 amount,
    uint256 slippage
  ) public {
    fromDecimals = uint8(bound(fromDecimals, 0, MAX_FUZZ_DECIMALS));
    toDecimals = uint8(bound(toDecimals, 0, MAX_FUZZ_DECIMALS));
    priceFrom = bound(priceFrom, 1, MAX_FUZZ_PRICE);
    priceTo = bound(priceTo, 1, MAX_FUZZ_PRICE);
    amount = bound(amount, 0, MAX_FUZZ_AMOUNT);
    slippage = bound(slippage, 0, TEST_BPS);

    uint256 expected = amount * priceFrom * 10 ** toDecimals / (priceTo * 10 ** fromDecimals);
    expected = expected * (TEST_BPS - slippage) / TEST_BPS;

    uint256 out = harness.getMinOut(
      _newMockToken(fromDecimals),
      _newMockToken(toDecimals),
      _newMockOracle(int256(priceFrom)),
      _newMockOracle(int256(priceTo)),
      amount,
      slippage
    );
    assertEq(out, expected);
  }

  function _newMockToken(uint8 decimals) internal returns (address) {
    return address(deployMockERC20("Token", "TOK", decimals));
  }

  function _newMockOracle(int256 answer) internal returns (address) {
    return address(new MockAggregator(answer));
  }
}
