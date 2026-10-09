// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardCancelSwapTest is SwapStewardTestBase {
  uint256 internal constant DONATION = 1e6;

  function test_cancelSwap_revertsWith_OnlyGuardianOrOwnerInvalidCaller() public {
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.cancelSwap(escrow);
  }

  function test_cancelSwap_revertsWith_SwapNotFound() public {
    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.SwapNotFound.selector);
    steward.cancelSwap(alice);
  }

  function test_cancelSwap() public {
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);
    (, bytes32 orderHash) = steward.swaps(escrow);
    deal(fromToken, escrow, swapAmount + DONATION);

    vm.expectEmit(address(steward));
    emit ISwapSteward.SwapCanceled(escrow, orderHash, fromToken, swapAmount + DONATION);
    vm.prank(executor);
    steward.cancelSwap(escrow);

    (address swapFromToken, bytes32 swapHash) = steward.swaps(escrow);
    assertEq(swapFromToken, address(0));
    assertEq(swapHash, bytes32(0));
    assertFalse(composableCow.singleOrders(escrow, orderHash));
    assertEq(IERC20(fromToken).allowance(escrow, vaultRelayer), 0);
    assertEq(IERC20(fromToken).balanceOf(escrow), 0);
    assertEq(IERC20(fromToken).balanceOf(collector), COLLECTOR_BALANCE + DONATION);
    assertEq(steward.tokenBudget(fromToken), guardianBudget - swapAmount);

    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.SwapNotFound.selector);
    steward.cancelSwap(escrow);
  }
}
