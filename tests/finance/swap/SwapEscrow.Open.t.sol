// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ComposableCoW} from "composable-cow/ComposableCoW.sol";
import {IConditionalOrder} from "composable-cow/interfaces/IConditionalOrder.sol";
import {SwapEscrow} from "src/finance/swap/SwapEscrow.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapEscrowOpenTest is SwapStewardTestBase {
  uint256 internal constant OPEN_ALLOWANCE = 7;

  function test_open_revertsWith_OnlySteward() public {
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);

    vm.prank(alice);
    vm.expectRevert(SwapEscrow.OnlySteward.selector);
    SwapEscrow(escrow)
      .open(
        IConditionalOrder.ConditionalOrderParams(IConditionalOrder(address(0)), bytes32(0), ""), IERC20(fromToken), 1
      );
  }

  function test_open() public {
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);
    IConditionalOrder.ConditionalOrderParams memory params =
      IConditionalOrder.ConditionalOrderParams(IConditionalOrder(twapHandler), bytes32(uint256(1)), "");
    bytes32 orderHash = keccak256(abi.encode(params));
    assertFalse(composableCow.singleOrders(escrow, orderHash));

    vm.expectEmit(true, true, true, true, address(composableCow));
    emit ComposableCoW.ConditionalOrderCreated(escrow, params);
    vm.prank(address(steward));
    SwapEscrow(escrow).open(params, IERC20(fromToken), OPEN_ALLOWANCE);

    assertTrue(composableCow.singleOrders(escrow, orderHash));
    assertEq(IERC20(fromToken).allowance(escrow, vaultRelayer), OPEN_ALLOWANCE);
  }
}
