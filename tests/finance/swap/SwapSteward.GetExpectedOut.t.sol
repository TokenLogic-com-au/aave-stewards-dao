// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {MockAggregator} from "tests/finance/swap/OracleMocks.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardGetExpectedOutTest is SwapStewardTestBase {
  uint256 internal constant MAX_FUZZ_AMOUNT = 1e30;
  uint256 internal constant MAX_FUZZ_PRICE = 1e12;

  function test_getExpectedOut_revertsWith_OracleNotSet_fromOracleUnset() public {
    vm.expectRevert(ISwapSteward.OracleNotSet.selector);
    steward.getExpectedOut(1e18, otherToken, toToken);
  }

  function test_getExpectedOut_revertsWith_OracleNotSet_toOracleUnset() public {
    vm.expectRevert(ISwapSteward.OracleNotSet.selector);
    steward.getExpectedOut(1e18, toToken, otherToken);
  }

  function test_getExpectedOut() public view {
    assertEq(steward.getExpectedOut(swapAmount, fromToken, toToken), EXPECTED_OUT);
    assertEq(steward.getExpectedOut(10 * swapAmount, fromToken, toToken), 10 * EXPECTED_OUT);
    assertEq(steward.getExpectedOut(0, fromToken, toToken), 0);
  }

  function test_fuzz_getExpectedOut_exactFloor(uint256 amount, uint256 priceFrom, uint256 priceTo) public {
    amount = bound(amount, 0, MAX_FUZZ_AMOUNT);
    priceFrom = bound(priceFrom, 1, MAX_FUZZ_PRICE);
    priceTo = bound(priceTo, 1, MAX_FUZZ_PRICE);
    vm.startPrank(executor);
    steward.setTokenOracle(fromToken, address(new MockAggregator(int256(priceFrom))));
    steward.setTokenOracle(toToken, address(new MockAggregator(int256(priceTo))));
    vm.stopPrank();

    uint256 expected = amount * priceFrom * 10 ** TO_DECIMALS / (priceTo * 10 ** FROM_DECIMALS);

    assertEq(steward.getExpectedOut(amount, fromToken, toToken), expected);
  }
}
