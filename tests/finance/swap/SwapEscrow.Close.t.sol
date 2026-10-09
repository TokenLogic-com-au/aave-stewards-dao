// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SwapEscrow} from "src/finance/swap/SwapEscrow.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapEscrowCloseTest is SwapStewardTestBase {
  function test_close_revertsWith_OnlySteward() public {
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);
    (, bytes32 orderHash) = steward.swaps(escrow);

    vm.prank(alice);
    vm.expectRevert(SwapEscrow.OnlySteward.selector);
    SwapEscrow(escrow).close(orderHash, IERC20(fromToken), alice);
  }

  function test_close() public {
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);
    (, bytes32 orderHash) = steward.swaps(escrow);

    vm.prank(address(steward));
    uint256 returned = SwapEscrow(escrow).close(orderHash, IERC20(fromToken), alice);

    assertEq(returned, swapAmount);
    assertFalse(composableCow.singleOrders(escrow, orderHash));
    assertEq(IERC20(fromToken).allowance(escrow, vaultRelayer), 0);
    assertEq(IERC20(fromToken).balanceOf(escrow), 0);
    assertEq(IERC20(fromToken).balanceOf(alice), swapAmount);
  }
}
