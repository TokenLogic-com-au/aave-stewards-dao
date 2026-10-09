// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorInterface} from "aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {IConditionalOrder} from "composable-cow/interfaces/IConditionalOrder.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
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
    assertEq(orderHash, keccak256(abi.encode(_marketParams(_marketData(guardianBudget, validUntil)))));
  }

  function test_swap_maxAmount_owner() public {
    uint32 validUntil = uint32(block.timestamp + 1 days);

    address escrow = _swap(executor, fromToken, toToken, type(uint256).max);

    assertEq(IERC20(fromToken).balanceOf(escrow), COLLECTOR_BALANCE);
    assertEq(IERC20(fromToken).balanceOf(collector), 0);
    assertEq(steward.tokenBudget(fromToken), guardianBudget);
    (, bytes32 orderHash) = steward.swaps(escrow);
    assertEq(orderHash, keccak256(abi.encode(_marketParams(_marketData(COLLECTOR_BALANCE, validUntil)))));
  }

  function test_swap() public {
    address expectedEscrow = _expectedEscrow();
    IConditionalOrder.ConditionalOrderParams memory params =
      _marketParams(_marketData(swapAmount, uint32(block.timestamp + 1 days)));

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
  }

  function _mockLatestAnswer(address oracle, int256 answer) internal {
    vm.mockCall(oracle, abi.encodeWithSelector(AggregatorInterface.latestAnswer.selector), abi.encode(answer));
  }
}
