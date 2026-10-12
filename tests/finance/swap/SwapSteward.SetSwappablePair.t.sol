// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardSetSwappablePairTest is SwapStewardTestBase {
  function test_setSwappablePair_revertsWith_OwnableUnauthorizedAccount() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.setSwappablePair(fromToken, otherToken);
  }

  function test_setSwappablePair_revertsWith_UnrecognizedTokenSwap_sameToken() public {
    vm.prank(executor);
    vm.expectRevert(ISwapSteward.UnrecognizedTokenSwap.selector);
    steward.setSwappablePair(fromToken, fromToken);
  }

  function test_setSwappablePair_revertsWith_SwappablePairAlreadySet() public {
    vm.startPrank(executor);
    steward.setSwappablePair(fromToken, otherToken);

    vm.expectRevert(ISwapSteward.SwappablePairAlreadySet.selector);
    steward.setSwappablePair(fromToken, otherToken);
    vm.stopPrank();
  }

  function test_setSwappablePair() public {
    assertFalse(steward.swapApprovedPair(fromToken, otherToken));

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.SetSwappablePair(fromToken, otherToken);
    vm.prank(executor);
    steward.setSwappablePair(fromToken, otherToken);

    assertTrue(steward.swapApprovedPair(fromToken, otherToken));
    assertFalse(steward.swapApprovedPair(otherToken, fromToken));
  }
}
