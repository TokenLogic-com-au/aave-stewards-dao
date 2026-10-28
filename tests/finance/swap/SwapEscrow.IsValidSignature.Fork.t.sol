// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC1271} from "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import {AggregatorInterface} from "aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol";
import {IConditionalOrder} from "src/finance/interfaces/IConditionalOrder.sol";
import {INVALID_HASH} from "src/finance/BaseConditionalOrder.sol";
import {GPv2Order} from "src/finance/libraries/GPv2Order.sol";
import {PercentageMath} from "aave-v3-origin/contracts/protocol/libraries/math/PercentageMath.sol";
import {ERC1271Forwarder} from "src/finance/ERC1271Forwarder.sol";
import {SwapEscrow} from "src/finance/swap/SwapEscrow.sol";
import {SwapStewardMainnetForkTestBase} from "tests/finance/swap/SwapStewardMainnetForkTestBase.sol";
import {ORDER_EXPIRED} from "src/finance/swap/OracleMarketOrder.sol";

contract SwapEscrowIsValidSignatureForkTest is SwapStewardMainnetForkTestBase {
  function test_isValidSignature_revertsWith_InvalidHash() public {
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);

    (GPv2Order.Data memory order, bytes memory signature) =
      _getMarketOrderWithSignature(escrow, uint32(block.timestamp + steward.ORDER_LIFETIME()));

    order.buyAmount -= 1;
    deal(address(order.buyToken), address(settlement), order.buyAmount);
    vm.expectRevert(ERC1271Forwarder.InvalidHash.selector);
    _settle(escrow, order, signature);
  }

  function test_isValidSignature_revertsWith_OrderNotValid_oracleMoved() public {
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);
    uint32 validTo = uint32(block.timestamp + steward.ORDER_LIFETIME());

    (GPv2Order.Data memory order, bytes memory signature) = _getMarketOrderWithSignature(escrow, validTo);

    int256 currentAnswer = AggregatorInterface(toOracle).latestAnswer();
    _mockLatestAnswer(
      toOracle,
      currentAnswer * int256(PercentageMath.PERCENTAGE_FACTOR + ORACLE_MOVE_BPS)
        / int256(PercentageMath.PERCENTAGE_FACTOR)
    );

    (GPv2Order.Data memory refreshed,) = _getMarketOrderWithSignature(escrow, validTo);
    assertNotEq(refreshed.buyAmount, order.buyAmount);
    deal(address(refreshed.buyToken), address(settlement), refreshed.buyAmount);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, INVALID_HASH));
    _settle(escrow, order, signature);
  }

  function test_isValidSignature() public {
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);
    uint32 validTo = uint32(block.timestamp + steward.ORDER_LIFETIME());

    (GPv2Order.Data memory order, bytes memory signature) = _getMarketOrderWithSignature(escrow, validTo);

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

    vm.warp(validTo + 1);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, ORDER_EXPIRED));
    composableCow.getTradeableOrderWithSignature(
      escrow, _marketParams(_marketData(swapAmount, validTo)), "", new bytes32[](0)
    );
  }
}
