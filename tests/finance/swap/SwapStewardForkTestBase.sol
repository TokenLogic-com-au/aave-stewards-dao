// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {GPv2Order} from "src/finance/libraries/GPv2Order.sol";
import {PercentageMath} from "aave-v3-origin/contracts/protocol/libraries/math/PercentageMath.sol";
import {AggregatorInterface} from "aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol";
import {IConditionalOrder} from "src/finance/interfaces/IConditionalOrder.sol";
import {TWAPOrder} from "src/finance/libraries/TWAPOrder.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {COMPOSABLE_COW, TWAP_HANDLER, VAULT_RELAYER} from "scripts/DeploySwapSteward.s.sol";
import {SwapStewardTestUtils} from "tests/finance/swap/SwapStewardTestUtils.sol";
import {IComposableCow} from "src/finance/interfaces/IComposableCow.sol";
import {IGPv2Settlement} from "src/finance/interfaces/IGPv2Settlement.sol";

/**
 * @dev Fork integration test for SwapSteward contract, run once per chain against the live Collector, ComposableCoW,
 * TWAP handler, GPv2Settlement and Chainlink oracles. Logic and revert paths live in the unit fixture on a pinned mainnet fork test suites
 * `tests/finance/swap/SwapSteward.*.t.sol` and `tests/finance/swap/SwapEscrow.*.t.sol`.
 * command: forge test -vvv --match-path 'tests/finance/swap/SwapStewardFork.*.t.sol'
 */
abstract contract SwapStewardForkTestBase is SwapStewardTestUtils {
  struct ChainConfig {
    string rpcAlias;
    uint256 forkBlock;
    address executor;
    address collector;
    address sequencerUptimeFeed;
    address fromToken;
    address fromOracle;
    address toToken;
    address toOracle;
    uint256 swapAmount;
    uint256 guardianBudget;
    uint256 twapPartAmount;
    uint256 twapMinPartLimit;
  }

  function _config() internal view virtual returns (ChainConfig memory);

  function setUp() public {
    ChainConfig memory cfg = _config();
    vm.createSelectFork(vm.rpcUrl(cfg.rpcAlias), cfg.forkBlock);

    executor = cfg.executor;
    collector = cfg.collector;
    sequencerUptimeFeed = cfg.sequencerUptimeFeed;
    fromToken = cfg.fromToken;
    fromOracle = cfg.fromOracle;
    toToken = cfg.toToken;
    toOracle = cfg.toOracle;
    swapAmount = cfg.swapAmount;
    guardianBudget = cfg.guardianBudget;
    twapPartAmount = cfg.twapPartAmount;
    twapMinPartLimit = cfg.twapMinPartLimit;

    composableCow = IComposableCow(COMPOSABLE_COW);
    twapHandler = TWAP_HANDLER;
    settlement = IGPv2Settlement(GPV2_SETTLEMENT);
    vaultRelayer = address(settlement.vaultRelayer());
    assertEq(vaultRelayer, VAULT_RELAYER);

    _deploySteward();
    _allowSolver();
  }

  function test_swap() public {
    uint256 collectorBalanceBefore = IERC20(fromToken).balanceOf(collector);
    assertGe(collectorBalanceBefore, swapAmount);

    address expectedEscrow = _expectedEscrow();
    IConditionalOrder.ConditionalOrderParams memory params =
      _marketParams(_marketData(swapAmount, uint32(block.timestamp + steward.ORDER_LIFETIME())));

    vm.expectEmit(true, true, true, true, address(composableCow));
    emit IComposableCow.ConditionalOrderCreated(expectedEscrow, params);
    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.SwapRequested(
      expectedEscrow, keccak256(abi.encode(params)), fromToken, toToken, fromOracle, toOracle, swapAmount, SWAP_SLIPPAGE
    );
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);
    (address swapFromToken, bytes32 orderHash) = steward.swaps(escrow);

    assertEq(swapFromToken, fromToken);
    assertTrue(composableCow.singleOrders(escrow, orderHash));
    assertEq(IERC20(fromToken).balanceOf(escrow), swapAmount);
    assertEq(IERC20(fromToken).balanceOf(address(steward)), 0);
    assertEq(IERC20(fromToken).balanceOf(collector), collectorBalanceBefore - swapAmount);
    assertEq(IERC20(fromToken).allowance(escrow, vaultRelayer), swapAmount);
    assertEq(steward.guardianTokenBudget(fromToken), guardianBudget - swapAmount);

    assertEq(keccak256(abi.encode(params)), orderHash);

    (GPv2Order.Data memory order, bytes memory signature) =
      _getMarketOrderWithSignature(escrow, uint32(block.timestamp + steward.ORDER_LIFETIME()));

    uint256 expectedBuyAmount =
      _expectedOut(swapAmount) * (PercentageMath.PERCENTAGE_FACTOR - SWAP_SLIPPAGE) / PercentageMath.PERCENTAGE_FACTOR;

    assertEq(address(order.sellToken), fromToken);
    assertEq(address(order.buyToken), toToken);
    assertEq(order.receiver, collector);
    assertEq(order.sellAmount, swapAmount);
    assertGt(expectedBuyAmount, 0);
    assertEq(order.buyAmount, expectedBuyAmount);
    assertEq(order.validTo, block.timestamp + steward.ORDER_LIFETIME());
    assertEq(order.appData, appData);
    assertEq(order.feeAmount, 0);
    assertEq(order.kind, GPv2Order.KIND_SELL);
    assertFalse(order.partiallyFillable);
    assertEq(order.sellTokenBalance, GPv2Order.BALANCE_ERC20);
    assertEq(order.buyTokenBalance, GPv2Order.BALANCE_ERC20);

    uint256 collectorBuyBefore = IERC20(toToken).balanceOf(collector);
    deal(toToken, GPV2_SETTLEMENT, order.buyAmount);
    _settle(escrow, order, signature);

    assertEq(IERC20(toToken).balanceOf(collector), collectorBuyBefore + expectedBuyAmount);
    assertEq(IERC20(fromToken).balanceOf(escrow), 0);
    assertEq(settlement.filledAmount(_orderUid(escrow, order)), swapAmount);
  }

  function test_cancelSwap() public {
    uint256 collectorBalanceBefore = IERC20(fromToken).balanceOf(collector);

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
    assertEq(IERC20(fromToken).balanceOf(collector), collectorBalanceBefore);

    IConditionalOrder.ConditionalOrderParams memory params =
      _marketParams(_marketData(swapAmount, uint32(block.timestamp + steward.ORDER_LIFETIME())));
    assertEq(keccak256(abi.encode(params)), orderHash);
    vm.expectRevert(IComposableCow.SingleOrderNotAuthed.selector);
    composableCow.getTradeableOrderWithSignature(escrow, params, "", new bytes32[](0));

    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.SwapNotFound.selector);
    steward.cancelSwap(escrow);
  }

  function test_twapSwap_settleParts() public {
    uint256 total = twapPartAmount * TWAP_NUM_PARTS;
    uint256 collectorBalanceBefore = IERC20(fromToken).balanceOf(collector);
    uint256 collectorBuyBefore = IERC20(toToken).balanceOf(collector);
    uint256 t0 = block.timestamp + TWAP_PART_DURATION;

    TWAPOrder.Data memory data = _twapData(t0, 0);
    IConditionalOrder.ConditionalOrderParams memory params = _twapParams(data);
    bytes32 expectedHash = keccak256(abi.encode(params));
    address expectedEscrow = _expectedEscrow();

    vm.expectEmit(true, true, true, true, address(composableCow));
    emit IComposableCow.ConditionalOrderCreated(expectedEscrow, params);
    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.TWAPSwapRequested(expectedEscrow, expectedHash, fromToken, toToken, total);
    address escrow = _twapSwap(guardian, data);
    assertEq(escrow, expectedEscrow);

    (address swapFromToken, bytes32 orderHash) = steward.swaps(escrow);
    assertEq(swapFromToken, fromToken);
    assertEq(orderHash, expectedHash);
    assertTrue(composableCow.singleOrders(escrow, expectedHash));
    assertEq(IERC20(fromToken).balanceOf(escrow), total);
    assertEq(IERC20(fromToken).balanceOf(address(steward)), 0);
    assertEq(IERC20(fromToken).balanceOf(collector), collectorBalanceBefore - total);
    assertEq(IERC20(fromToken).allowance(escrow, vaultRelayer), total);
    assertEq(steward.guardianTokenBudget(fromToken), guardianBudget - total);

    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, BEFORE_TWAP_START));
    _getTwapOrderWithSignature(escrow, t0);

    vm.warp(t0);
    (GPv2Order.Data memory first, bytes memory firstSignature) = _getTwapOrderWithSignature(escrow, t0);

    assertEq(address(first.sellToken), fromToken);
    assertEq(address(first.buyToken), toToken);
    assertEq(first.receiver, collector);
    assertEq(first.sellAmount, twapPartAmount);
    assertEq(first.buyAmount, twapMinPartLimit);
    assertEq(first.validTo, t0 + TWAP_PART_DURATION - 1);
    assertEq(first.appData, appData);
    assertEq(first.feeAmount, 0);
    assertEq(first.kind, GPv2Order.KIND_SELL);
    assertFalse(first.partiallyFillable);
    assertEq(first.sellTokenBalance, GPv2Order.BALANCE_ERC20);
    assertEq(first.buyTokenBalance, GPv2Order.BALANCE_ERC20);

    deal(toToken, GPV2_SETTLEMENT, first.buyAmount);
    _settle(escrow, first, firstSignature);

    assertEq(IERC20(toToken).balanceOf(collector), collectorBuyBefore + twapMinPartLimit);
    assertEq(settlement.filledAmount(_orderUid(escrow, first)), twapPartAmount);
    assertEq(first.sellToken.balanceOf(escrow), twapPartAmount * (TWAP_NUM_PARTS - 1));
    assertEq(first.sellToken.allowance(escrow, vaultRelayer), twapPartAmount * (TWAP_NUM_PARTS - 1));

    vm.expectRevert(abi.encodeWithSignature("Error(string)", GPV2_ORDER_FILLED));
    _settle(escrow, first, firstSignature);

    vm.warp(t0 + TWAP_PART_DURATION);
    (GPv2Order.Data memory second, bytes memory secondSignature) = _getTwapOrderWithSignature(escrow, t0);

    assertEq(second.validTo, t0 + 2 * TWAP_PART_DURATION - 1);
    assertNotEq(_orderUid(escrow, second), _orderUid(escrow, first));

    deal(toToken, GPV2_SETTLEMENT, second.buyAmount);
    _settle(escrow, second, secondSignature);

    assertEq(IERC20(toToken).balanceOf(collector), collectorBuyBefore + 2 * twapMinPartLimit);
    assertEq(settlement.filledAmount(_orderUid(escrow, second)), twapPartAmount);
    assertEq(first.sellToken.balanceOf(escrow), twapPartAmount * (TWAP_NUM_PARTS - 2));
  }

  function _expectedOut(uint256 amount) internal view returns (uint256) {
    uint256 priceFrom = uint256(AggregatorInterface(fromOracle).latestAnswer());
    uint256 priceTo = uint256(AggregatorInterface(toOracle).latestAnswer());
    return (amount * priceFrom * 10 ** IERC20Metadata(toToken).decimals())
      / (priceTo * 10 ** IERC20Metadata(fromToken).decimals());
  }
}
