// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {IConditionalOrder} from "composable-cow/interfaces/IConditionalOrder.sol";
import {
  TWAPOrder,
  INVALID_TOKEN,
  INVALID_MIN_PART_LIMIT,
  INVALID_START_TIME,
  INVALID_NUM_PARTS,
  INVALID_FREQUENCY,
  INVALID_SPAN
} from "composable-cow/types/twap/libraries/TWAPOrder.sol";
import {BEFORE_TWAP_START} from "composable-cow/types/twap/libraries/TWAPOrderMathLib.sol";
import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {IERC20 as GPv2IERC20} from "cowprotocol/contracts/interfaces/IERC20.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardTwapSwapTest is SwapStewardTestBase {
  struct OrderBoundsCase {
    TWAPOrder.Data data;
    address caller;
    string invalidReason;
  }

  function test_twapSwap_revertsWith_OnlyGuardianOrOwnerInvalidCaller() public {
    TWAPOrder.Data memory data = _twapData(0, 0);

    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    _twapSwap(alice, data);
  }

  function test_twapSwap_revertsWith_InvalidZeroAmount() public {
    TWAPOrder.Data memory data = _twapData(0, 0);
    data.partSellAmount = 0;

    vm.expectRevert(ISwapSteward.InvalidZeroAmount.selector);
    _twapSwap(guardian, data);
  }

  function test_twapSwap_revertsWith_UnrecognizedTokenSwap_pairNotApproved() public {
    TWAPOrder.Data memory data = _twapData(0, 0);
    data.buyToken = GPv2IERC20(otherToken);

    vm.expectRevert(ISwapSteward.UnrecognizedTokenSwap.selector);
    _twapSwap(guardian, data);
  }

  function test_twapSwap_revertsWith_InsufficientBudget() public {
    TWAPOrder.Data memory data = _twapData(0, 0);
    data.partSellAmount = guardianBudget / TWAP_NUM_PARTS + 1;

    vm.expectRevert(ISwapSteward.InsufficientBudget.selector);
    _twapSwap(guardian, data);
  }

  function test_twapSwap_revertsWith_StartTimeInPast() public {
    TWAPOrder.Data memory data = _twapData(block.timestamp - 1, 0);

    vm.expectRevert(ISwapSteward.StartTimeInPast.selector);
    _twapSwap(guardian, data);
  }

  function test_twapSwap_orderBounds() public {
    vm.prank(executor);
    steward.setSwappablePair(fromToken, address(0), true);
    deal(fromToken, collector, uint256(type(uint32).max) + 2 * twapPartAmount);

    OrderBoundsCase[] memory cases = new OrderBoundsCase[](10);
    for (uint256 i; i < cases.length; i++) {
      cases[i] = OrderBoundsCase({data: _twapData(block.timestamp, 0), caller: guardian, invalidReason: ""});
    }
    cases[0].data.t0 = type(uint32).max;
    cases[0].invalidReason = INVALID_START_TIME;
    cases[1].data.buyToken = GPv2IERC20(address(0));
    cases[1].invalidReason = INVALID_TOKEN;
    cases[2].data.minPartLimit = 0;
    cases[2].invalidReason = INVALID_MIN_PART_LIMIT;
    cases[3].data.n = 1;
    cases[3].invalidReason = INVALID_NUM_PARTS;
    cases[4].data.n = uint256(type(uint32).max) + 1;
    cases[4].invalidReason = INVALID_NUM_PARTS;
    cases[5].data.t = 0;
    cases[5].invalidReason = INVALID_FREQUENCY;
    cases[6].data.t = TWAP_MAX_PART_DURATION + 1;
    cases[6].invalidReason = INVALID_FREQUENCY;
    cases[7].data.span = TWAP_PART_DURATION + 1;
    cases[7].invalidReason = INVALID_SPAN;
    cases[8].data.n = 2;
    cases[8].data.t = TWAP_MAX_PART_DURATION;
    cases[8].data.span = TWAP_MAX_PART_DURATION;
    cases[9].data.partSellAmount = 1;
    cases[9].data.n = type(uint32).max;
    cases[9].caller = executor;

    for (uint256 i; i < cases.length; i++) {
      OrderBoundsCase memory c = cases[i];
      if (bytes(c.invalidReason).length != 0) {
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, c.invalidReason));
        _twapSwap(c.caller, c.data);
      } else {
        address escrow = _twapSwap(c.caller, c.data);
        (, bytes32 orderHash) = steward.swaps(escrow);
        assertEq(orderHash, keccak256(abi.encode(_twapParams(c.data))));
        assertEq(IERC20(fromToken).balanceOf(escrow), c.data.partSellAmount * c.data.n);
      }
    }
  }

  function test_twapSwap() public {
    uint256 total = twapPartAmount * TWAP_NUM_PARTS;

    TWAPOrder.Data memory data = _twapData(block.timestamp + TWAP_PART_DURATION, 0);
    IConditionalOrder.ConditionalOrderParams memory params = _twapParams(data);
    bytes32 expectedHash = keccak256(abi.encode(params));
    address expectedEscrow = _expectedEscrow();

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.TWAPSwapRequested(expectedEscrow, expectedHash, fromToken, toToken, total);
    address escrow = _twapSwap(guardian, data);

    (address swapFromToken, bytes32 orderHash) = steward.swaps(escrow);
    assertEq(escrow, expectedEscrow);
    assertEq(swapFromToken, fromToken);
    assertEq(orderHash, expectedHash);
    assertTrue(composableCow.singleOrders(escrow, expectedHash));
    assertEq(IERC20(fromToken).balanceOf(escrow), total);
    assertEq(IERC20(fromToken).balanceOf(address(steward)), 0);
    assertEq(IERC20(fromToken).balanceOf(collector), COLLECTOR_BALANCE - total);
    assertEq(IERC20(fromToken).allowance(escrow, vaultRelayer), total);
    assertEq(steward.tokenBudget(fromToken), guardianBudget - total);

    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, BEFORE_TWAP_START));
    composableCow.getTradeableOrderWithSignature(escrow, params, "", new bytes32[](0));
  }

  function test_twapSwap_startTimeZero() public {
    uint256 t0 = block.timestamp;

    address escrow = _twapSwap(guardian, _twapData(0, 0));

    (, bytes32 orderHash) = steward.swaps(escrow);
    assertEq(orderHash, keccak256(abi.encode(_twapParams(_twapData(t0, 0)))));
  }

  function test_twapSwap_startTimeNow() public {
    uint256 t0 = block.timestamp;

    address escrow = _twapSwap(guardian, _twapData(t0, 0));

    (, bytes32 orderHash) = steward.swaps(escrow);
    assertEq(orderHash, keccak256(abi.encode(_twapParams(_twapData(t0, 0)))));
  }

  function test_twapSwap_ownerSkipsBudget() public {
    TWAPOrder.Data memory data = _twapData(0, 0);
    data.partSellAmount = guardianBudget / TWAP_NUM_PARTS + swapAmount / 10;
    uint256 total = data.partSellAmount * TWAP_NUM_PARTS;
    assertGt(total, guardianBudget);

    address escrow = _twapSwap(executor, data);

    assertEq(steward.tokenBudget(fromToken), guardianBudget);
    assertEq(IERC20(fromToken).balanceOf(escrow), total);
  }

  function test_twapSwap_settleParts() public {
    uint256 t0 = block.timestamp;
    address escrow = _twapSwap(guardian, _twapData(0, 0));

    (GPv2Order.Data memory first, bytes memory firstSignature) = _getTwapOrderWithSignature(escrow, t0);

    deal(toToken, address(settlement), first.buyAmount);
    _settle(escrow, first, firstSignature);

    assertEq(IERC20(toToken).balanceOf(collector), twapMinPartLimit);
    assertEq(settlement.filledAmount(_orderUid(escrow, first)), twapPartAmount);
    assertEq(first.sellToken.balanceOf(escrow), twapPartAmount * (TWAP_NUM_PARTS - 1));
    assertEq(first.sellToken.allowance(escrow, vaultRelayer), twapPartAmount * (TWAP_NUM_PARTS - 1));

    vm.expectRevert(abi.encodeWithSignature("Error(string)", GPV2_ORDER_FILLED));
    _settle(escrow, first, firstSignature);

    vm.warp(t0 + TWAP_PART_DURATION);
    (GPv2Order.Data memory second, bytes memory secondSignature) = _getTwapOrderWithSignature(escrow, t0);

    assertEq(second.validTo, t0 + 2 * TWAP_PART_DURATION - 1);
    assertNotEq(_orderUid(escrow, second), _orderUid(escrow, first));

    deal(toToken, address(settlement), second.buyAmount);
    _settle(escrow, second, secondSignature);

    assertEq(IERC20(toToken).balanceOf(collector), 2 * twapMinPartLimit);
    assertEq(settlement.filledAmount(_orderUid(escrow, second)), twapPartAmount);
    assertEq(first.sellToken.balanceOf(escrow), twapPartAmount * (TWAP_NUM_PARTS - 2));
  }

  function test_twapSwap_cancelAfterPart() public {
    uint256 t0 = block.timestamp;
    address escrow = _twapSwap(guardian, _twapData(0, 0));
    (, bytes32 orderHash) = steward.swaps(escrow);

    (GPv2Order.Data memory first, bytes memory signature) = _getTwapOrderWithSignature(escrow, t0);
    deal(toToken, address(settlement), first.buyAmount);
    _settle(escrow, first, signature);

    uint256 remainder = twapPartAmount * (TWAP_NUM_PARTS - 1);
    vm.expectEmit(address(steward));
    emit ISwapSteward.SwapCanceled(escrow, orderHash, fromToken, remainder);
    vm.prank(guardian);
    steward.cancelSwap(escrow);

    (address swapFromToken, bytes32 swapHash) = steward.swaps(escrow);
    assertEq(swapFromToken, address(0));
    assertEq(swapHash, bytes32(0));
    assertFalse(composableCow.singleOrders(escrow, orderHash));
    assertEq(IERC20(fromToken).allowance(escrow, vaultRelayer), 0);
    assertEq(IERC20(fromToken).balanceOf(escrow), 0);
    assertEq(IERC20(fromToken).balanceOf(collector), COLLECTOR_BALANCE - twapPartAmount);
  }

  function test_twapSwap_twoSameFromToken() public {
    uint256 total = twapPartAmount * TWAP_NUM_PARTS;
    TWAPOrder.Data memory data = _twapData(block.timestamp, 0);

    address first = _twapSwap(guardian, data);
    address second = _twapSwap(guardian, data);

    assertNotEq(first, second);
    assertEq(IERC20(fromToken).balanceOf(first), total);
    assertEq(IERC20(fromToken).balanceOf(second), total);
    assertEq(IERC20(fromToken).allowance(first, vaultRelayer), total);
    assertEq(IERC20(fromToken).allowance(second, vaultRelayer), total);

    (, bytes32 firstHash) = steward.swaps(first);
    (, bytes32 secondHash) = steward.swaps(second);
    assertEq(firstHash, secondHash);
    assertTrue(composableCow.singleOrders(first, firstHash));
    assertTrue(composableCow.singleOrders(second, secondHash));

    vm.prank(guardian);
    steward.cancelSwap(first);

    assertFalse(composableCow.singleOrders(first, firstHash));
    assertTrue(composableCow.singleOrders(second, secondHash));
    assertEq(IERC20(fromToken).balanceOf(second), total);
    assertEq(IERC20(fromToken).allowance(second, vaultRelayer), total);
  }
}
