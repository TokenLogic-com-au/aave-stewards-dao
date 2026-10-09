// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardCancelSwapTest is SwapStewardTestBase {
  function test_cancelSwap_revertsWith_OnlyGuardianOrOwnerInvalidCaller() public {
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);
    (address swapFromToken, bytes32 orderHash) = steward.swaps(escrow);

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.cancelSwap(escrow);

    (address fromTokenAfter, bytes32 orderHashAfter) = steward.swaps(escrow);
    assertEq(fromTokenAfter, swapFromToken);
    assertEq(orderHashAfter, orderHash);
    assertTrue(composableCow.singleOrders(escrow, orderHash));
    assertEq(IERC20(fromToken).balanceOf(escrow), swapAmount);
    assertEq(IERC20(fromToken).allowance(escrow, vaultRelayer), swapAmount);
  }

  function test_cancelSwap_revertsWith_SwapNotFound() public {
    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.SwapNotFound.selector);
    steward.cancelSwap(alice);
  }

  function test_cancelSwap() public {
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);
    (, bytes32 orderHash) = steward.swaps(escrow);

    vm.expectEmit(address(steward));
    emit ISwapSteward.SwapCanceled(escrow, orderHash, fromToken, swapAmount);
    vm.prank(guardian);
    steward.cancelSwap(escrow);

    (address swapFromToken, bytes32 swapHash) = steward.swaps(escrow);
    assertEq(swapFromToken, address(0));
    assertEq(swapHash, bytes32(0));
    assertFalse(composableCow.singleOrders(escrow, orderHash));
    assertEq(IERC20(fromToken).allowance(escrow, vaultRelayer), 0);
    assertEq(IERC20(fromToken).balanceOf(escrow), 0);
    assertEq(IERC20(fromToken).balanceOf(collector), COLLECTOR_BALANCE);

    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.SwapNotFound.selector);
    steward.cancelSwap(escrow);
  }
}
