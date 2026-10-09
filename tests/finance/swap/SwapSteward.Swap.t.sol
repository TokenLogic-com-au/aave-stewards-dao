// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC1271} from "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import {AggregatorInterface} from "aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {IConditionalOrder} from "composable-cow/interfaces/IConditionalOrder.sol";
import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {OracleMarketOrder} from "src/finance/swap/OracleMarketOrder.sol";
import {SwapEscrow} from "src/finance/swap/SwapEscrow.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardSwapTest is SwapStewardTestBase {
  function test_swap_revertsWith_OnlyGuardianOrOwnerInvalidCaller() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.swap(fromToken, toToken, swapAmount, SWAP_SLIPPAGE);
  }

  function test_swap_revertsWith_InvalidZeroAmount() public {
    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.InvalidZeroAmount.selector);
    steward.swap(fromToken, toToken, 0, SWAP_SLIPPAGE);
  }

  function test_swap_revertsWith_UnrecognizedTokenSwap_pairNotApproved() public {
    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.UnrecognizedTokenSwap.selector);
    steward.swap(fromToken, otherToken, swapAmount, SWAP_SLIPPAGE);
  }

  function test_swap_revertsWith_UnrecognizedTokenSwap_reversedPair() public {
    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.UnrecognizedTokenSwap.selector);
    steward.swap(toToken, fromToken, swapAmount, SWAP_SLIPPAGE);
  }

  function test_swap_revertsWith_OracleNotSet_fromOracleUnset() public {
    _approvePairsWithOtherToken();

    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.OracleNotSet.selector);
    steward.swap(otherToken, fromToken, swapAmount, SWAP_SLIPPAGE);
  }

  function test_swap_revertsWith_OracleNotSet_toOracleUnset() public {
    _approvePairsWithOtherToken();

    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.OracleNotSet.selector);
    steward.swap(fromToken, otherToken, swapAmount, SWAP_SLIPPAGE);
  }

  function test_swap_revertsWith_InvalidSlippage() public {
    vm.startPrank(guardian);
    steward.swap(fromToken, toToken, swapAmount, MAX_SLIPPAGE);

    vm.expectRevert(ISwapSteward.InvalidSlippage.selector);
    steward.swap(fromToken, toToken, swapAmount, MAX_SLIPPAGE + 1);
    vm.stopPrank();
  }

  function test_swap_revertsWith_PriceFeedInvalidAnswer_fromOracleZero() public {
    _mockLatestAnswer(fromOracle, 0);

    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.PriceFeedInvalidAnswer.selector);
    steward.swap(fromToken, toToken, swapAmount, SWAP_SLIPPAGE);
  }

  function test_swap_revertsWith_PriceFeedInvalidAnswer_fromOracleNegative() public {
    _mockLatestAnswer(fromOracle, -1);

    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.PriceFeedInvalidAnswer.selector);
    steward.swap(fromToken, toToken, swapAmount, SWAP_SLIPPAGE);
  }

  function test_swap_revertsWith_PriceFeedInvalidAnswer_toOracleZero() public {
    _mockLatestAnswer(toOracle, 0);

    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.PriceFeedInvalidAnswer.selector);
    steward.swap(fromToken, toToken, swapAmount, SWAP_SLIPPAGE);
  }

  function test_swap_revertsWith_PriceFeedInvalidAnswer_toOracleNegative() public {
    _mockLatestAnswer(toOracle, -1);

    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.PriceFeedInvalidAnswer.selector);
    steward.swap(fromToken, toToken, swapAmount, SWAP_SLIPPAGE);
  }

  function test_swap_revertsWith_InsufficientBudget() public {
    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.InsufficientBudget.selector);
    steward.swap(fromToken, toToken, guardianBudget + 1, SWAP_SLIPPAGE);
  }

  function test_swap_ownerSkipsBudget() public {
    uint256 amount = guardianBudget + swapAmount / 10;

    address escrow = _swap(executor, fromToken, toToken, amount);

    assertEq(steward.tokenBudget(fromToken), guardianBudget);
    assertEq(IERC20(fromToken).balanceOf(escrow), amount);
    assertEq(IERC20(fromToken).balanceOf(collector), COLLECTOR_BALANCE - amount);
  }

  function test_swap_maxAmount_guardian() public {
    uint32 validUntil = uint32(block.timestamp + 1 days);

    address escrow = _swap(guardian, fromToken, toToken, type(uint256).max);

    assertEq(IERC20(fromToken).balanceOf(escrow), guardianBudget);
    assertEq(IERC20(fromToken).balanceOf(collector), COLLECTOR_BALANCE - guardianBudget);
    assertEq(steward.tokenBudget(fromToken), 0);
    (, bytes32 orderHash) = steward.swaps(escrow);
    assertEq(
      orderHash, keccak256(abi.encode(_marketParams(_marketData(fromToken, toToken, guardianBudget, validUntil))))
    );
  }

  function test_swap_maxAmount_owner() public {
    uint32 validUntil = uint32(block.timestamp + 1 days);

    address escrow = _swap(executor, fromToken, toToken, type(uint256).max);

    assertEq(IERC20(fromToken).balanceOf(escrow), COLLECTOR_BALANCE);
    assertEq(IERC20(fromToken).balanceOf(collector), 0);
    assertEq(steward.tokenBudget(fromToken), guardianBudget);
    (, bytes32 orderHash) = steward.swaps(escrow);
    assertEq(
      orderHash, keccak256(abi.encode(_marketParams(_marketData(fromToken, toToken, COLLECTOR_BALANCE, validUntil))))
    );
  }

  function test_swap() public {
    address expectedEscrow = _expectedEscrow();
    IConditionalOrder.ConditionalOrderParams memory params =
      _marketParams(_marketData(fromToken, toToken, swapAmount, uint32(block.timestamp + 1 days)));

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.SwapRequested(
      expectedEscrow, keccak256(abi.encode(params)), fromToken, toToken, fromOracle, toOracle, swapAmount, SWAP_SLIPPAGE
    );
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);

    (address swapFromToken, bytes32 orderHash) = steward.swaps(escrow);
    assertEq(escrow, expectedEscrow);
    assertEq(swapFromToken, fromToken);
    assertEq(orderHash, keccak256(abi.encode(params)));
    assertTrue(composableCow.singleOrders(escrow, orderHash));
    assertEq(IERC20(fromToken).balanceOf(escrow), swapAmount);
    assertEq(IERC20(fromToken).balanceOf(address(steward)), 0);
    assertEq(IERC20(fromToken).balanceOf(collector), COLLECTOR_BALANCE - swapAmount);
    assertEq(IERC20(fromToken).allowance(escrow, vaultRelayer), swapAmount);
    assertEq(steward.tokenBudget(fromToken), guardianBudget - swapAmount);

    (GPv2Order.Data memory order, bytes memory signature) =
      composableCow.getTradeableOrderWithSignature(escrow, params, "", new bytes32[](0));

    assertEq(address(order.sellToken), fromToken);
    assertEq(address(order.buyToken), toToken);
    assertEq(order.receiver, collector);
    assertEq(order.sellAmount, swapAmount);
    assertEq(order.buyAmount, EXPECTED_BUY_AMOUNT);
    assertEq(order.validTo, block.timestamp + 1 days);
    assertEq(order.appData, APP_DATA);
    assertEq(order.feeAmount, 0);
    assertEq(order.kind, GPv2Order.KIND_SELL);
    assertFalse(order.partiallyFillable);
    assertEq(order.sellTokenBalance, GPv2Order.BALANCE_ERC20);
    assertEq(order.buyTokenBalance, GPv2Order.BALANCE_ERC20);

    bytes32 orderDigest = GPv2Order.hash(order, settlement.domainSeparator());
    assertEq(SwapEscrow(escrow).isValidSignature(orderDigest, signature), IERC1271.isValidSignature.selector);
  }

  function test_swap_twoSwapsSameFromToken() public {
    address first = _swap(guardian, fromToken, toToken, swapAmount);
    address second = _swap(guardian, fromToken, toToken, 2 * swapAmount);

    assertNotEq(first, second);
    assertEq(IERC20(fromToken).balanceOf(first), swapAmount);
    assertEq(IERC20(fromToken).balanceOf(second), 2 * swapAmount);
    assertEq(IERC20(fromToken).allowance(first, vaultRelayer), swapAmount);
    assertEq(IERC20(fromToken).allowance(second, vaultRelayer), 2 * swapAmount);

    (, bytes32 firstHash) = steward.swaps(first);
    (, bytes32 secondHash) = steward.swaps(second);
    assertTrue(composableCow.singleOrders(first, firstHash));
    assertTrue(composableCow.singleOrders(second, secondHash));
  }

  function test_fuzz_swap_guardianBudget(uint256 amount) public {
    amount = bound(amount, 1, guardianBudget);

    address escrow = _swap(guardian, fromToken, toToken, amount);

    assertEq(steward.tokenBudget(fromToken), guardianBudget - amount);
    assertEq(IERC20(fromToken).balanceOf(escrow), amount);
    assertEq(IERC20(fromToken).balanceOf(collector), COLLECTOR_BALANCE - amount);
    assertEq(IERC20(fromToken).allowance(escrow, vaultRelayer), amount);
  }

  function test_fuzz_swap_revertsWith_InsufficientBudget(uint256 amount) public {
    amount = bound(amount, guardianBudget + 1, COLLECTOR_BALANCE);

    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.InsufficientBudget.selector);
    steward.swap(fromToken, toToken, amount, SWAP_SLIPPAGE);
  }

  function test_fuzz_swap_orderBuyAmount(uint256 amount, uint256 slippage) public {
    amount = bound(amount, 1, guardianBudget);
    slippage = bound(slippage, 0, MAX_SLIPPAGE);

    address escrow = _expectedEscrow();
    vm.prank(guardian);
    steward.swap(fromToken, toToken, amount, slippage);

    OracleMarketOrder.Data memory data = _marketData(fromToken, toToken, amount, uint32(block.timestamp + 1 days));
    data.slippage = slippage;
    IConditionalOrder.ConditionalOrderParams memory params = _marketParams(data);
    (, bytes32 orderHash) = steward.swaps(escrow);
    (GPv2Order.Data memory order,) = composableCow.getTradeableOrderWithSignature(escrow, params, "", new bytes32[](0));

    assertEq(orderHash, keccak256(abi.encode(params)));
    assertEq(order.sellAmount, amount);
    assertEq(order.buyAmount, amount * OUT_PER_FROM_UNIT * (BPS - slippage) / BPS);
  }

  function test_fuzz_swap_revertsWith_InvalidSlippage(uint256 slippage) public {
    slippage = bound(slippage, MAX_SLIPPAGE + 1, type(uint64).max);

    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.InvalidSlippage.selector);
    steward.swap(fromToken, toToken, swapAmount, slippage);
  }

  function _mockLatestAnswer(address oracle, int256 answer) internal {
    vm.mockCall(oracle, abi.encodeWithSelector(AggregatorInterface.latestAnswer.selector), abi.encode(answer));
  }
}
