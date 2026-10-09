// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardGetExpectedOutTest is SwapStewardTestBase {
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
}
