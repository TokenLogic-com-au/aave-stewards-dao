// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC1271} from "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import {AggregatorInterface} from "aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol";
import {IConditionalOrder} from "composable-cow/interfaces/IConditionalOrder.sol";
import {INVALID_HASH} from "composable-cow/BaseConditionalOrder.sol";
import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {ERC1271Forwarder} from "src/finance/ERC1271Forwarder.sol";
import {SwapEscrow} from "src/finance/swap/SwapEscrow.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapEscrowIsValidSignatureTest is SwapStewardTestBase {
  function test_isValidSignature_revertsWith_InvalidHash() public {
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);

    (GPv2Order.Data memory order, bytes memory signature) =
      _getMarketOrderWithSignature(escrow, uint32(block.timestamp + 1 days));

    order.buyAmount -= 1;
    deal(address(order.buyToken), address(settlement), order.buyAmount);
    vm.expectRevert(ERC1271Forwarder.InvalidHash.selector);
    _settle(escrow, order, signature);
  }

  function test_isValidSignature_revertsWith_OrderNotValid_oracleMoved() public {
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);
    uint32 validUntil = uint32(block.timestamp + 1 days);

    (GPv2Order.Data memory order, bytes memory signature) = _getMarketOrderWithSignature(escrow, validUntil);

    int256 currentAnswer = AggregatorInterface(toOracle).latestAnswer();
    vm.mockCall(
      toOracle,
      abi.encodeWithSelector(AggregatorInterface.latestAnswer.selector),
      abi.encode(currentAnswer * int256(BPS + ORACLE_MOVE_BPS) / int256(BPS))
    );

    (GPv2Order.Data memory refreshed,) = _getMarketOrderWithSignature(escrow, validUntil);
    assertNotEq(refreshed.buyAmount, order.buyAmount);
    deal(address(refreshed.buyToken), address(settlement), refreshed.buyAmount);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, INVALID_HASH));
    _settle(escrow, order, signature);
  }

  function test_isValidSignature_stableWithinOracleRound() public {
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);
    uint32 validUntil = uint32(block.timestamp + 1 days);

    (GPv2Order.Data memory first, bytes memory firstSignature) = _getMarketOrderWithSignature(escrow, validUntil);

    vm.warp(block.timestamp + 1 hours);

    (GPv2Order.Data memory second,) = _getMarketOrderWithSignature(escrow, validUntil);

    bytes32 domainSeparator = settlement.domainSeparator();
    assertEq(GPv2Order.hash(first, domainSeparator), GPv2Order.hash(second, domainSeparator));
    assertEq(first.validTo, second.validTo);
    assertEq(_orderUid(escrow, first), _orderUid(escrow, second));
    deal(address(first.buyToken), address(settlement), first.buyAmount);

    _settle(escrow, first, firstSignature);
    assertEq(settlement.filledAmount(_orderUid(escrow, first)), swapAmount);
  }

  function test_isValidSignature() public {
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);
    uint32 validUntil = uint32(block.timestamp + 1 days);

    (GPv2Order.Data memory order, bytes memory signature) = _getMarketOrderWithSignature(escrow, validUntil);

    assertEq(order.buyAmount, EXPECTED_BUY_AMOUNT);
    assertEq(
      SwapEscrow(escrow).isValidSignature(GPv2Order.hash(order, settlement.domainSeparator()), signature),
      IERC1271.isValidSignature.selector
    );

    deal(toToken, address(settlement), order.buyAmount);
    _settle(escrow, order, signature);

    assertEq(IERC20(toToken).balanceOf(collector), EXPECTED_BUY_AMOUNT);
    assertEq(IERC20(toToken).balanceOf(address(settlement)), 0);
    assertEq(IERC20(fromToken).balanceOf(escrow), 0);
    assertEq(IERC20(fromToken).balanceOf(address(settlement)), swapAmount);
    assertEq(settlement.filledAmount(_orderUid(escrow, order)), swapAmount);
  }
}
