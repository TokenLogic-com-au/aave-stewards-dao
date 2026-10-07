// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AaveV3Arbitrum, AaveV3ArbitrumAssets} from "aave-address-book/AaveV3Arbitrum.sol";
import {ChainlinkArbitrum} from "aave-address-book/ChainlinkArbitrum.sol";
import {GovernanceV3Arbitrum} from "aave-address-book/GovernanceV3Arbitrum.sol";
import {IGPv2Settlement} from "src/finance/interfaces/IGPv2Settlement.sol";
import {IAggregatorInterface} from "src/finance/interfaces/IAggregatorInterface.sol";
import {IComposableCow} from "src/finance/interfaces/IComposableCow.sol";
import {IConditionalOrder} from "src/finance/interfaces/IConditionalOrder.sol";
import {GPv2Order} from "src/finance/libraries/GPv2Order.sol";
import {OracleMarketOrder} from "src/finance/OracleMarketOrder.sol";
import {ISwapSteward} from "src/finance/interfaces/ISwapSteward.sol";
import {SwapOrder} from "src/finance/SwapOrder.sol";
import {SwapSteward} from "src/finance/SwapSteward.sol";

/**
 * @dev Test for SwapSteward contract
 * command: forge test -vvv --match-path tests/finance/SwapSteward.t.sol
 */
contract SwapStewardTest is Test {
  // https://arbiscan.io/address/0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74
  address internal constant COMPOSABLE_COW = 0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74;

  // https://arbiscan.io/address/0x6cF1e9cA41f7611dEf408122793c358a3d11E5a5
  address internal constant TWAP_HANDLER = 0x6cF1e9cA41f7611dEf408122793c358a3d11E5a5;

  // https://arbiscan.io/address/0x9008D19f58AAbD9eD0D60971565AA8510560ab41
  address internal constant GPV2_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;

  // https://arbiscan.io/address/0xC92E8bdf79f0507f65a392b0ab4667716BFE0110
  address internal constant VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

  uint256 internal constant FORK_BLOCK = 512244730;
  bytes32 internal constant APP_DATA = bytes32(0);
  bytes32 internal constant FUNDS_ADMIN_ROLE = bytes32("FUNDS_ADMIN");
  bytes4 internal constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
  uint256 internal constant BPS = 100_00;
  uint256 internal constant SWAP_SLIPPAGE = 50;
  uint256 internal constant SWAP_AMOUNT = 10e6;
  uint256 internal constant GUARDIAN_BUDGET = 50e6;

  address public guardian = makeAddr("guardian");
  address public alice = makeAddr("alice");
  address public limitOrderHandler = makeAddr("limitOrderHandler");

  OracleMarketOrder public marketOrderHandler;
  SwapSteward public steward;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("arbitrum"), FORK_BLOCK);

    marketOrderHandler = new OracleMarketOrder();
    steward = new SwapSteward(
      GovernanceV3Arbitrum.EXECUTOR_LVL_1,
      guardian,
      address(AaveV3Arbitrum.COLLECTOR),
      COMPOSABLE_COW,
      address(marketOrderHandler),
      limitOrderHandler,
      TWAP_HANDLER,
      VAULT_RELAYER,
      ChainlinkArbitrum.L2_Sequencer_Uptime_Status_Feed
    );

    vm.startPrank(GovernanceV3Arbitrum.EXECUTOR_LVL_1);
    IAccessControl(address(AaveV3Arbitrum.COLLECTOR)).grantRole(FUNDS_ADMIN_ROLE, address(steward));
    steward.setSwappablePair(AaveV3ArbitrumAssets.USDCn_UNDERLYING, AaveV3ArbitrumAssets.WETH_UNDERLYING, true);
    steward.setTokenOracle(AaveV3ArbitrumAssets.USDCn_UNDERLYING, AaveV3ArbitrumAssets.USDCn_ORACLE);
    steward.setTokenOracle(AaveV3ArbitrumAssets.WETH_UNDERLYING, AaveV3ArbitrumAssets.WETH_ORACLE);
    steward.increaseTokenBudget(AaveV3ArbitrumAssets.USDCn_UNDERLYING, GUARDIAN_BUDGET);
    vm.stopPrank();
  }

  function test_constructor() public {}

  function test_revertsIf_collectorIsZeroAddress() public {}

  function test_revertsIf_composableCowIsZeroAddress() public {}

  function test_revertsIf_handlerIsZeroAddress() public {}

  function test_revertsIf_vaultRelayerIsZeroAddress() public {}

  function test_transferOwnership() public {}

  function test_updateGuardian_revertsIf_notOwnerOrGuardian() public {}

  function test_updateGuardian() public {}

  function test_rescueToken_revertsIf_notOwnerOrGuardian() public {}

  function test_rescueToken() public {}

  function test_rescueToken_amount() public {}

  function test_setSwappablePair_revertsIf_notOwner() public {}

  function test_setSwappablePair_revertsIf_sameToken() public {}

  function test_setSwappablePair() public {}

  function test_setTokenOracle_revertsIf_notOwner() public {}

  function test_setTokenOracle_revertsIf_zeroAddress() public {}

  function test_setTokenOracle_revertsIf_incompatibleDecimals() public {}

  function test_setTokenOracle_revertsIf_invalidAnswer() public {}

  function test_setTokenOracle() public {}

  function test_increaseTokenBudget_revertsIf_notOwner() public {}

  function test_increaseTokenBudget() public {}

  function test_decreaseTokenBudget_revertsIf_notOwner() public {}

  function test_decreaseTokenBudget_revertsIf_insufficientBudget() public {}

  function test_decreaseTokenBudget() public {}

  function test_swap_revertsIf_notOwnerOrGuardian() public {}

  function test_swap_revertsIf_zeroAmount() public {}

  function test_swap_revertsIf_unrecognizedPair() public {}

  function test_swap_revertsIf_oracleNotSet() public {}

  function test_swap_revertsIf_slippageAboveMax() public {}

  function test_swap_revertsIf_invalidPriceFeedAnswer() public {}

  function test_swap_revertsIf_budgetExceeded() public {}

  function test_swap_success_ownerSkipsBudget() public {}

  function test_swap_success_guardianConsumesBudget() public {}

  function test_swap_success_maxAmount() public {}

  function test_swap_success() public {
    address fromToken = AaveV3ArbitrumAssets.USDCn_UNDERLYING;
    address toToken = AaveV3ArbitrumAssets.WETH_UNDERLYING;
    address collector = address(AaveV3Arbitrum.COLLECTOR);
    uint256 collectorBalanceBefore = IERC20(fromToken).balanceOf(collector);
    assertGe(collectorBalanceBefore, SWAP_AMOUNT);

    address swapOrder = _swap(guardian, fromToken, toToken, SWAP_AMOUNT);
    (address swapFromToken, bytes32 orderHash) = steward.swaps(swapOrder);

    assertEq(swapFromToken, fromToken);
    assertNotEq(orderHash, bytes32(0));
    assertTrue(IComposableCow(COMPOSABLE_COW).singleOrders(swapOrder, orderHash));
    assertEq(IERC20(fromToken).balanceOf(swapOrder), SWAP_AMOUNT);
    assertEq(IERC20(fromToken).balanceOf(address(steward)), 0);
    assertEq(IERC20(fromToken).balanceOf(collector), collectorBalanceBefore - SWAP_AMOUNT);
    assertEq(IERC20(fromToken).allowance(swapOrder, VAULT_RELAYER), SWAP_AMOUNT);
    assertEq(steward.tokenBudget(fromToken), GUARDIAN_BUDGET - SWAP_AMOUNT);

    IConditionalOrder.ConditionalOrderParams memory params = IConditionalOrder.ConditionalOrderParams(
      IConditionalOrder(address(marketOrderHandler)),
      bytes32(0),
      abi.encode(
        OracleMarketOrder.Data({
          fromToken: fromToken,
          toToken: toToken,
          fromOracle: AaveV3ArbitrumAssets.USDCn_ORACLE,
          toOracle: AaveV3ArbitrumAssets.WETH_ORACLE,
          receiver: collector,
          sellAmount: SWAP_AMOUNT,
          slippage: SWAP_SLIPPAGE,
          appData: APP_DATA,
          validUntil: uint32(block.timestamp + 1 days),
          sequencerUptimeFeed: ChainlinkArbitrum.L2_Sequencer_Uptime_Status_Feed,
          sequencerGracePeriod: 1 hours
        })
      )
    );
    assertEq(keccak256(abi.encode(params)), orderHash);

    (GPv2Order.Data memory order, bytes memory signature) =
      IComposableCow(COMPOSABLE_COW).getTradeableOrderWithSignature(swapOrder, params, "", new bytes32[](0));

    uint256 pFrom = uint256(IAggregatorInterface(AaveV3ArbitrumAssets.USDCn_ORACLE).latestAnswer());
    uint256 pTo = uint256(IAggregatorInterface(AaveV3ArbitrumAssets.WETH_ORACLE).latestAnswer());
    uint256 expectedBuyAmount = (SWAP_AMOUNT * pFrom * 10 ** IERC20Metadata(toToken).decimals())
      / (pTo * 10 ** IERC20Metadata(fromToken).decimals()) * (BPS - SWAP_SLIPPAGE) / BPS;

    assertEq(address(order.sellToken), fromToken);
    assertEq(address(order.buyToken), toToken);
    assertEq(order.receiver, collector);
    assertEq(order.sellAmount, SWAP_AMOUNT);
    assertGt(expectedBuyAmount, 0);
    assertEq(order.buyAmount, expectedBuyAmount);
    assertEq(order.validTo, block.timestamp + 1 days);
    assertEq(order.appData, APP_DATA);
    assertEq(order.feeAmount, 0);
    assertEq(order.kind, GPv2Order.KIND_SELL);
    assertFalse(order.partiallyFillable);
    assertEq(order.sellTokenBalance, GPv2Order.BALANCE_ERC20);
    assertEq(order.buyTokenBalance, GPv2Order.BALANCE_ERC20);

    bytes32 orderDigest = GPv2Order.hash(order, IGPv2Settlement(GPV2_SETTLEMENT).domainSeparator());
    assertEq(SwapOrder(swapOrder).isValidSignature(orderDigest, signature), ERC1271_MAGIC_VALUE);
  }

  function test_swap_emitsSwapRequested() public {}

  function test_swap_twoSwapsSameFromToken() public {
    address fromToken = AaveV3ArbitrumAssets.USDCn_UNDERLYING;
    address toToken = AaveV3ArbitrumAssets.WETH_UNDERLYING;

    address first = _swap(guardian, fromToken, toToken, SWAP_AMOUNT);
    address second = _swap(guardian, fromToken, toToken, 2 * SWAP_AMOUNT);

    assertNotEq(first, second);
    assertEq(IERC20(fromToken).balanceOf(first), SWAP_AMOUNT);
    assertEq(IERC20(fromToken).balanceOf(second), 2 * SWAP_AMOUNT);
    assertEq(IERC20(fromToken).allowance(first, VAULT_RELAYER), SWAP_AMOUNT);
    assertEq(IERC20(fromToken).allowance(second, VAULT_RELAYER), 2 * SWAP_AMOUNT);

    (, bytes32 firstHash) = steward.swaps(first);
    (, bytes32 secondHash) = steward.swaps(second);
    assertTrue(IComposableCow(COMPOSABLE_COW).singleOrders(first, firstHash));
    assertTrue(IComposableCow(COMPOSABLE_COW).singleOrders(second, secondHash));
  }

  function test_swap_approvesVaultRelayer() public {}

  function test_limitSwap_revertsIf_unrecognizedPair() public {}

  function test_limitSwap_success() public {}

  function test_twapSwap_revertsIf_unrecognizedPair() public {}

  function test_twapSwap_success() public {}

  function test_cancelSwap_revertsIf_notOwnerOrGuardian() public {}

  function test_cancelSwap_revertsIf_swapNotFound() public {
    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.SwapNotFound.selector);
    steward.cancelSwap(alice);
  }

  function test_cancelSwap_beforeFill() public {
    address fromToken = AaveV3ArbitrumAssets.USDCn_UNDERLYING;
    address collector = address(AaveV3Arbitrum.COLLECTOR);
    uint256 collectorBalanceBefore = IERC20(fromToken).balanceOf(collector);

    address swapOrder = _swap(guardian, fromToken, AaveV3ArbitrumAssets.WETH_UNDERLYING, SWAP_AMOUNT);
    (, bytes32 orderHash) = steward.swaps(swapOrder);

    vm.expectEmit(address(steward));
    emit ISwapSteward.SwapCanceled(swapOrder, orderHash, fromToken, SWAP_AMOUNT);
    vm.prank(guardian);
    steward.cancelSwap(swapOrder);

    (address swapFromToken, bytes32 swapHash) = steward.swaps(swapOrder);
    assertEq(swapFromToken, address(0));
    assertEq(swapHash, bytes32(0));
    assertFalse(IComposableCow(COMPOSABLE_COW).singleOrders(swapOrder, orderHash));
    assertEq(IERC20(fromToken).allowance(swapOrder, VAULT_RELAYER), 0);
    assertEq(IERC20(fromToken).balanceOf(swapOrder), 0);
    assertEq(IERC20(fromToken).balanceOf(collector), collectorBalanceBefore);
  }

  function test_cancelSwap_revertsIf_alreadyCanceled() public {
    address swapOrder =
      _swap(guardian, AaveV3ArbitrumAssets.USDCn_UNDERLYING, AaveV3ArbitrumAssets.WETH_UNDERLYING, SWAP_AMOUNT);

    vm.startPrank(guardian);
    steward.cancelSwap(swapOrder);
    vm.expectRevert(ISwapSteward.SwapNotFound.selector);
    steward.cancelSwap(swapOrder);
    vm.stopPrank();
  }

  function test_swapOrder_revertsIf_notSteward() public {
    address swapOrder =
      _swap(guardian, AaveV3ArbitrumAssets.USDCn_UNDERLYING, AaveV3ArbitrumAssets.WETH_UNDERLYING, SWAP_AMOUNT);
    (, bytes32 orderHash) = steward.swaps(swapOrder);

    vm.startPrank(alice);
    vm.expectRevert(SwapOrder.OnlySteward.selector);
    SwapOrder(swapOrder).close(orderHash, IERC20(AaveV3ArbitrumAssets.USDCn_UNDERLYING), alice);
    vm.expectRevert(SwapOrder.OnlySteward.selector);
    SwapOrder(swapOrder)
      .open(
        IConditionalOrder.ConditionalOrderParams(IConditionalOrder(address(0)), bytes32(0), ""),
        IERC20(AaveV3ArbitrumAssets.USDCn_UNDERLYING),
        1
      );
    vm.stopPrank();
  }

  function test_cancelSwap_afterPartialFill() public {}

  function test_cancelSwap_afterFill() public {}

  function test_swap_afterCancel() public {}

  function test_isValidSignature_revertsIf_invalidHash() public {}

  function test_isValidSignature_revertsIf_orderCanceled() public {}

  function test_isValidSignature() public {}

  function test_getExpectedOut_revertsIf_oracleNotSet() public {}

  function test_getExpectedOut() public {}

  function test_settle() public {}

  function test_settle_revertsIf_worseBuyAmount() public {}

  function test_settle_revertsIf_afterOracleRoundChange() public {}

  function _swap(address caller, address fromToken, address toToken, uint256 amount) internal returns (address) {
    address swapOrder = vm.computeCreateAddress(address(steward), vm.getNonce(address(steward)));
    vm.prank(caller);
    steward.swap(fromToken, toToken, amount, SWAP_SLIPPAGE);
    return swapOrder;
  }
}
