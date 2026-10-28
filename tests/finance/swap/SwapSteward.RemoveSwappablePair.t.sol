// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardRemoveSwappablePairTest is SwapStewardTestBase {
  function test_removeSwappablePair_revertsWith_OwnableUnauthorizedAccount() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.removeSwappablePair(fromToken, toToken);
  }

  function test_removeSwappablePair_revertsWith_UnrecognizedTokenSwap() public {
    vm.prank(executor);
    vm.expectRevert(ISwapSteward.UnrecognizedTokenSwap.selector);
    steward.removeSwappablePair(fromToken, otherToken);
  }

  function test_removeSwappablePair() public {
    assertTrue(steward.swapApprovedPair(fromToken, toToken));

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.SwappablePairRemoved(fromToken, toToken);
    vm.prank(executor);
    steward.removeSwappablePair(fromToken, toToken);

    assertFalse(steward.swapApprovedPair(fromToken, toToken));
  }

  function test_removeSwappablePair_setAfterRemove() public {
    vm.startPrank(executor);
    steward.removeSwappablePair(fromToken, toToken);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.SetSwappablePair(fromToken, toToken);
    steward.setSwappablePair(fromToken, toToken);
    vm.stopPrank();

    assertTrue(steward.swapApprovedPair(fromToken, toToken));
  }
}
