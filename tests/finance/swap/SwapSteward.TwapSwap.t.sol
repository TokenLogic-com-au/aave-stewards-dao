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
import {BEFORE_TWAP_START, AFTER_TWAP_FINISH} from "composable-cow/types/twap/libraries/TWAPOrderMathLib.sol";
import {NOT_WITHIN_SPAN} from "composable-cow/types/twap/TWAP.sol";
import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {IERC20 as GPv2IERC20} from "cowprotocol/contracts/interfaces/IERC20.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardTwapSwapTest is SwapStewardTestBase {
  uint256 internal constant MAX_FUZZ_PARTS = 20;

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

  function test_twapSwap_revertsWith_UnrecognizedTokenSwap_reversedPair() public {
    TWAPOrder.Data memory data = _twapData(0, 0);
    (data.sellToken, data.buyToken) = (data.buyToken, data.sellToken);

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

  function test_twapSwap_revertsWith_OrderNotValid_startTimeTooLate() public {
    TWAPOrder.Data memory data = _twapData(type(uint32).max, 0);

    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, INVALID_START_TIME));
    _twapSwap(guardian, data);
  }

  function test_twapSwap_revertsWith_OrderNotValid_zeroBuyToken() public {
    vm.prank(executor);
    steward.setSwappablePair(fromToken, address(0), true);

    TWAPOrder.Data memory data = _twapData(0, 0);
    data.buyToken = GPv2IERC20(address(0));

    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, INVALID_TOKEN));
    _twapSwap(guardian, data);
  }

  function test_twapSwap_revertsWith_OrderNotValid_zeroMinPartLimit() public {
    TWAPOrder.Data memory data = _twapData(0, 0);
    data.minPartLimit = 0;

    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, INVALID_MIN_PART_LIMIT));
    _twapSwap(guardian, data);
  }

  function test_twapSwap_revertsWith_OrderNotValid_numPartsTooLow() public {
    TWAPOrder.Data memory data = _twapData(0, 0);
    data.n = 1;

    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, INVALID_NUM_PARTS));
    _twapSwap(guardian, data);
  }

  function test_twapSwap_revertsWith_OrderNotValid_numPartsTooHigh() public {
    TWAPOrder.Data memory data = _twapData(0, 0);
    data.n = uint256(type(uint32).max) + 1;

    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, INVALID_NUM_PARTS));
    _twapSwap(guardian, data);
  }

  function test_twapSwap_revertsWith_OrderNotValid_zeroPartDuration() public {
    TWAPOrder.Data memory data = _twapData(0, 0);
    data.t = 0;

    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, INVALID_FREQUENCY));
    _twapSwap(guardian, data);
  }

  function test_twapSwap_revertsWith_OrderNotValid_partDurationTooHigh() public {
    TWAPOrder.Data memory data = _twapData(0, 0);
    data.t = TWAP_MAX_PART_DURATION + 1;

    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, INVALID_FREQUENCY));
    _twapSwap(guardian, data);
  }

  function test_twapSwap_revertsWith_OrderNotValid_spanAbovePartDuration() public {
    TWAPOrder.Data memory data = _twapData(0, TWAP_PART_DURATION + 1);

    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, INVALID_SPAN));
    _twapSwap(guardian, data);
  }

  function test_twapSwap_boundaryParameters() public {
    deal(fromToken, collector, uint256(type(uint32).max) + 2 * twapPartAmount);

    TWAPOrder.Data memory twoParts = _twapData(block.timestamp, TWAP_MAX_PART_DURATION);
    twoParts.n = 2;
    twoParts.t = TWAP_MAX_PART_DURATION;
    address twoPartsEscrow = _twapSwap(guardian, twoParts);
    (, bytes32 twoPartsHash) = steward.swaps(twoPartsEscrow);
    assertEq(twoPartsHash, keccak256(abi.encode(_twapParams(twoParts))));

    TWAPOrder.Data memory maxParts = _twapData(block.timestamp, 0);
    maxParts.partSellAmount = 1;
    maxParts.n = type(uint32).max;
    address maxPartsEscrow = _twapSwap(executor, maxParts);
    (, bytes32 maxPartsHash) = steward.swaps(maxPartsEscrow);
    assertEq(maxPartsHash, keccak256(abi.encode(_twapParams(maxParts))));
    assertEq(IERC20(fromToken).balanceOf(maxPartsEscrow), type(uint32).max);
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

    (GPv2Order.Data memory first, bytes memory firstSignature) = _getTwapOrderWithSignature(escrow, t0, 0);

    assertEq(address(first.sellToken), fromToken);
    assertEq(address(first.buyToken), toToken);
    assertEq(first.receiver, collector);
    assertEq(first.sellAmount, twapPartAmount);
    assertEq(first.buyAmount, twapMinPartLimit);
    assertEq(first.validTo, t0 + TWAP_PART_DURATION - 1);
    assertEq(first.appData, APP_DATA);
    assertEq(first.feeAmount, 0);
    assertEq(first.kind, GPv2Order.KIND_SELL);
    assertFalse(first.partiallyFillable);
    assertEq(first.sellTokenBalance, GPv2Order.BALANCE_ERC20);
    assertEq(first.buyTokenBalance, GPv2Order.BALANCE_ERC20);

    deal(toToken, address(settlement), first.buyAmount);
    _settle(escrow, first, firstSignature);

    assertEq(IERC20(toToken).balanceOf(collector), twapMinPartLimit);
    assertEq(settlement.filledAmount(_orderUid(escrow, first)), twapPartAmount);
    assertEq(first.sellToken.balanceOf(escrow), twapPartAmount * (TWAP_NUM_PARTS - 1));
    assertEq(first.sellToken.allowance(escrow, vaultRelayer), twapPartAmount * (TWAP_NUM_PARTS - 1));

    vm.expectRevert(abi.encodeWithSignature("Error(string)", GPV2_ORDER_FILLED));
    _settle(escrow, first, firstSignature);

    vm.warp(t0 + TWAP_PART_DURATION);
    (GPv2Order.Data memory second, bytes memory secondSignature) = _getTwapOrderWithSignature(escrow, t0, 0);

    assertEq(second.validTo, t0 + 2 * TWAP_PART_DURATION - 1);
    assertNotEq(_orderUid(escrow, second), _orderUid(escrow, first));

    deal(toToken, address(settlement), second.buyAmount);
    _settle(escrow, second, secondSignature);

    assertEq(IERC20(toToken).balanceOf(collector), 2 * twapMinPartLimit);
    assertEq(settlement.filledAmount(_orderUid(escrow, second)), twapPartAmount);
    assertEq(first.sellToken.balanceOf(escrow), twapPartAmount * (TWAP_NUM_PARTS - 2));
  }

  function test_twapSwap_span() public {
    uint256 t0 = block.timestamp;
    address escrow = _twapSwap(guardian, _twapData(0, TWAP_SPAN));

    (GPv2Order.Data memory first,) = _getTwapOrderWithSignature(escrow, t0, TWAP_SPAN);
    assertEq(first.validTo, t0 + TWAP_SPAN - 1);

    vm.warp(t0 + TWAP_SPAN);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, NOT_WITHIN_SPAN));
    _getTwapOrderWithSignature(escrow, t0, TWAP_SPAN);

    vm.warp(t0 + TWAP_PART_DURATION);
    (GPv2Order.Data memory second,) = _getTwapOrderWithSignature(escrow, t0, TWAP_SPAN);
    assertEq(second.validTo, t0 + TWAP_PART_DURATION + TWAP_SPAN - 1);
  }

  function test_twapSwap_cancelAfterPart() public {
    uint256 t0 = block.timestamp;
    address escrow = _twapSwap(guardian, _twapData(0, 0));
    (, bytes32 orderHash) = steward.swaps(escrow);

    (GPv2Order.Data memory first, bytes memory signature) = _getTwapOrderWithSignature(escrow, t0, 0);
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

  function test_twapSwap_afterFinish() public {
    uint256 t0 = block.timestamp;
    address escrow = _twapSwap(guardian, _twapData(0, 0));

    (GPv2Order.Data memory first, bytes memory signature) = _getTwapOrderWithSignature(escrow, t0, 0);
    deal(toToken, address(settlement), first.buyAmount);
    _settle(escrow, first, signature);

    uint256 finish = t0 + TWAP_NUM_PARTS * TWAP_PART_DURATION;
    vm.warp(finish - 1);
    (GPv2Order.Data memory last,) = _getTwapOrderWithSignature(escrow, t0, 0);
    assertEq(last.validTo, finish - 1);

    vm.warp(finish);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, AFTER_TWAP_FINISH));
    _getTwapOrderWithSignature(escrow, t0, 0);

    vm.prank(guardian);
    steward.cancelSwap(escrow);

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

  function test_fuzz_twapSwap_guardianBudget(uint256 partSellAmount, uint256 numParts) public {
    numParts = bound(numParts, 2, MAX_FUZZ_PARTS);
    partSellAmount = bound(partSellAmount, 1, guardianBudget / numParts);
    TWAPOrder.Data memory data = _twapData(0, 0);
    data.partSellAmount = partSellAmount;
    data.n = numParts;

    address escrow = _twapSwap(guardian, data);

    assertEq(IERC20(fromToken).balanceOf(escrow), partSellAmount * numParts);
    assertEq(IERC20(fromToken).allowance(escrow, vaultRelayer), partSellAmount * numParts);
    assertEq(steward.tokenBudget(fromToken), guardianBudget - partSellAmount * numParts);
  }

  function test_fuzz_twapSwap_revertsWith_InsufficientBudget(uint256 partSellAmount, uint256 numParts) public {
    numParts = bound(numParts, 2, MAX_FUZZ_PARTS);
    partSellAmount = bound(partSellAmount, guardianBudget / numParts + 1, COLLECTOR_BALANCE / numParts);
    TWAPOrder.Data memory data = _twapData(0, 0);
    data.partSellAmount = partSellAmount;
    data.n = numParts;

    vm.expectRevert(ISwapSteward.InsufficientBudget.selector);
    _twapSwap(guardian, data);
  }
}
