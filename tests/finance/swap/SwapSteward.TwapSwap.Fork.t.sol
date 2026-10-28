// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IConditionalOrder} from "src/finance/interfaces/IConditionalOrder.sol";
import {TWAPOrder} from "src/finance/libraries/TWAPOrder.sol";
import {GPv2Order} from "src/finance/libraries/GPv2Order.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardMainnetForkTestBase} from "tests/finance/swap/SwapStewardMainnetForkTestBase.sol";

contract SwapStewardTwapSwapForkTest is SwapStewardMainnetForkTestBase {
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
    assertEq(steward.guardianTokenBudget(fromToken), guardianBudget - total);

    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, BEFORE_TWAP_START));
    _getTwapOrderWithSignature(escrow, data.t0);
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
