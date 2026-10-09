// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardSetSwappablePairTest is SwapStewardTestBase {
  function test_setSwappablePair_revertsWith_OwnableUnauthorizedAccount() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.setSwappablePair(fromToken, otherToken, true);
  }

  function test_setSwappablePair_revertsWith_UnrecognizedTokenSwap() public {
    vm.prank(executor);
    vm.expectRevert(ISwapSteward.UnrecognizedTokenSwap.selector);
    steward.setSwappablePair(fromToken, fromToken, true);
  }

  function test_setSwappablePair() public {
    vm.startPrank(executor);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.SetSwappablePair(fromToken, otherToken, true);
    steward.setSwappablePair(fromToken, otherToken, true);

    assertTrue(steward.swapApprovedPair(fromToken, otherToken));
    assertFalse(steward.swapApprovedPair(otherToken, fromToken));

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.SetSwappablePair(fromToken, otherToken, false);
    steward.setSwappablePair(fromToken, otherToken, false);

    assertFalse(steward.swapApprovedPair(fromToken, otherToken));
    vm.stopPrank();
  }
}
