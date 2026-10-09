// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {GPv2Settlement} from "cowprotocol/contracts/GPv2Settlement.sol";
import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {AggregatorInterface} from "aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol";
import {ComposableCoW} from "composable-cow/ComposableCoW.sol";
import {IConditionalOrder} from "composable-cow/interfaces/IConditionalOrder.sol";
import {TWAPOrder} from "composable-cow/types/twap/libraries/TWAPOrder.sol";
import {BEFORE_TWAP_START} from "composable-cow/types/twap/libraries/TWAPOrderMathLib.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardTestUtils} from "tests/finance/swap/SwapStewardTestUtils.sol";

/**
 * @dev Fork integration test for SwapSteward contract, run once per chain against the live Collector, ComposableCoW,
 * TWAP handler, GPv2Settlement and Chainlink oracles. Logic and revert paths live in the non-fork suites
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

  // Canonical CoW deployments: the same CREATE2 address on every CoW chain, including Base (8453), which
  // composable-cow networks.json does not list.
  address internal constant COMPOSABLE_COW = 0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74;
  address internal constant TWAP_HANDLER = 0x6cF1e9cA41f7611dEf408122793c358a3d11E5a5;
  address internal constant GPV2_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
  address internal constant VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

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

    composableCow = ComposableCoW(COMPOSABLE_COW);
    twapHandler = TWAP_HANDLER;
    vaultRelayer = VAULT_RELAYER;
    settlement = GPv2Settlement(payable(GPV2_SETTLEMENT));

    _deploySteward();
    _allowSolver();
  }

  function test_swap() public {
    uint256 collectorBalanceBefore = IERC20(fromToken).balanceOf(collector);
    assertGe(collectorBalanceBefore, swapAmount);

    address expectedEscrow = _expectedEscrow();
    IConditionalOrder.ConditionalOrderParams memory params =
      _marketParams(_marketData(swapAmount, uint32(block.timestamp + 1 days)));

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
    assertEq(steward.tokenBudget(fromToken), guardianBudget - swapAmount);

    assertEq(keccak256(abi.encode(params)), orderHash);

    (GPv2Order.Data memory order, bytes memory signature) =
      composableCow.getTradeableOrderWithSignature(escrow, params, "", new bytes32[](0));

    uint256 expectedBuyAmount = _expectedOut(swapAmount) * (BPS - SWAP_SLIPPAGE) / BPS;

    assertEq(address(order.sellToken), fromToken);
    assertEq(address(order.buyToken), toToken);
    assertEq(order.receiver, collector);
    assertEq(order.sellAmount, swapAmount);
    assertGt(expectedBuyAmount, 0);
    assertEq(order.buyAmount, expectedBuyAmount);
    assertEq(order.validTo, block.timestamp + 1 days);
    assertEq(order.appData, APP_DATA);
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
    assertEq(steward.tokenBudget(fromToken), guardianBudget - total);

    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, BEFORE_TWAP_START));
    composableCow.getTradeableOrderWithSignature(escrow, params, "", new bytes32[](0));

    vm.warp(t0);
    (GPv2Order.Data memory first, bytes memory firstSignature) = _getTwapOrderWithSignature(escrow, t0);

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
    uint256 pFrom = uint256(AggregatorInterface(fromOracle).latestAnswer());
    uint256 pTo = uint256(AggregatorInterface(toOracle).latestAnswer());
    return
      (amount * pFrom * 10 ** IERC20Metadata(toToken).decimals()) / (pTo * 10 ** IERC20Metadata(fromToken).decimals());
  }
}
