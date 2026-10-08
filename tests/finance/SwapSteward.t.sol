// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC1271} from "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {AaveV3Arbitrum, AaveV3ArbitrumAssets} from "aave-address-book/AaveV3Arbitrum.sol";
import {ChainlinkArbitrum} from "aave-address-book/ChainlinkArbitrum.sol";
import {GovernanceV3Arbitrum} from "aave-address-book/GovernanceV3Arbitrum.sol";
import {IGPv2Settlement} from "src/finance/interfaces/IGPv2Settlement.sol";
import {IAggregatorInterface} from "src/finance/interfaces/IAggregatorInterface.sol";
import {IComposableCow} from "src/finance/interfaces/IComposableCow.sol";
import {IConditionalOrder} from "src/finance/interfaces/IConditionalOrder.sol";
import {GPv2Order} from "src/finance/libraries/GPv2Order.sol";
import {OracleMarketOrder} from "src/finance/OracleMarketOrder.sol";
import {INVALID_HASH} from "src/finance/BaseConditionalOrder.sol";
import {ERC1271Forwarder} from "src/finance/ERC1271Forwarder.sol";
import {ISwapSteward} from "src/finance/interfaces/ISwapSteward.sol";
import {SwapOrder} from "src/finance/SwapOrder.sol";
import {SwapSteward} from "src/finance/SwapSteward.sol";
import {MockOracle} from "tests/finance/MainnetSwapSteward.t.sol";

struct GPv2TradeData {
  uint256 sellTokenIndex;
  uint256 buyTokenIndex;
  address receiver;
  uint256 sellAmount;
  uint256 buyAmount;
  uint32 validTo;
  bytes32 appData;
  uint256 feeAmount;
  uint256 flags;
  uint256 executedAmount;
  bytes signature;
}

struct GPv2InteractionData {
  address target;
  uint256 value;
  bytes callData;
}

interface IGPv2SettlementTest {
  function settle(
    IERC20[] calldata tokens,
    uint256[] calldata clearingPrices,
    GPv2TradeData[] calldata trades,
    GPv2InteractionData[][3] calldata interactions
  ) external;
  function authenticator() external view returns (address);
  function filledAmount(bytes calldata orderUid) external view returns (uint256);
}

interface IGPv2AllowListAuthentication {
  function manager() external view returns (address);
  function addSolver(address solver) external;
}

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
  uint256 internal constant BPS = 100_00;
  uint256 internal constant SWAP_SLIPPAGE = 50;
  uint256 internal constant SWAP_AMOUNT = 10e6;
  uint256 internal constant GUARDIAN_BUDGET = 50e6;
  uint256 internal constant ORACLE_MOVE_BPS = 100;
  uint256 internal constant ARBITRUM_BLOCK_TIME = 1;
  /// @dev GPv2Trade flags: bits 0-4 = 0 (sell, fill-or-kill, ERC20 sell and buy balances); bits 5-6 = signing
  /// scheme, where GPv2Signing.Scheme.Eip1271 = 2.
  /// https://github.com/cowprotocol/contracts/blob/a10f40788af29467e87de3dbf2196662b0a6b500/src/contracts/libraries/GPv2Trade.sol#L58-L131
  /// https://github.com/cowprotocol/contracts/blob/a10f40788af29467e87de3dbf2196662b0a6b500/src/contracts/mixins/GPv2Signing.sol#L24-L29
  uint256 internal constant FLAGS_SELL_FILL_OR_KILL_EIP1271 = 2 << 5;
  string internal constant ORDER_EXPIRED = "order expired";

  address public guardian = makeAddr("guardian");
  address public alice = makeAddr("alice");
  address public limitOrderHandler = makeAddr("limitOrderHandler");
  address public solver = makeAddr("solver");

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

    address authenticator = IGPv2SettlementTest(GPV2_SETTLEMENT).authenticator();
    vm.prank(IGPv2AllowListAuthentication(authenticator).manager());
    IGPv2AllowListAuthentication(authenticator).addSolver(solver);
  }

  function test_constructor() public {}

  function test_revertsIf_collectorIsZeroAddress() public {}

  function test_revertsIf_composableCowIsZeroAddress() public {}

  function test_revertsIf_handlerIsZeroAddress() public {}

  function test_revertsIf_vaultRelayerIsZeroAddress() public {}

  function test_transferOwnership() public {}

  function test_updateGuardian_revertsIf_notOwnerOrGuardian() public {}

  function test_updateGuardian() public {}

  function test_rescueToken_revertsIf_notOwnerOrGuardian() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.rescueToken(AaveV3ArbitrumAssets.ARB_UNDERLYING);
    vm.stopPrank();
  }

  function test_rescueToken() public {
    address collector = address(AaveV3Arbitrum.COLLECTOR);
    address token = AaveV3ArbitrumAssets.ARB_UNDERLYING;
    uint256 amount = 1_000e18;

    deal(token, address(steward), amount);
    assertEq(IERC20(token).balanceOf(address(steward)), amount);

    uint256 collectorBefore = IERC20(token).balanceOf(collector);

    vm.prank(guardian);
    steward.rescueToken(token);

    assertEq(IERC20(token).balanceOf(address(steward)), 0);
    assertEq(IERC20(token).balanceOf(collector), collectorBefore + amount);
  }

  function test_rescueToken_amount() public {
    address collector = address(AaveV3Arbitrum.COLLECTOR);
    address token = AaveV3ArbitrumAssets.ARB_UNDERLYING;
    uint256 amount = 1_000e18;
    uint256 rescueAmount = 500e18;

    deal(token, address(steward), amount);
    uint256 collectorBefore = IERC20(token).balanceOf(collector);

    vm.prank(guardian);
    steward.rescueToken(token, rescueAmount);

    assertEq(IERC20(token).balanceOf(address(steward)), amount - rescueAmount);
    assertEq(IERC20(token).balanceOf(collector), collectorBefore + rescueAmount);
  }

  function test_setSwappablePair_revertsIf_notOwner() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.setSwappablePair(AaveV3ArbitrumAssets.USDCn_UNDERLYING, AaveV3ArbitrumAssets.ARB_UNDERLYING, true);
    vm.stopPrank();
  }

  function test_setSwappablePair_revertsIf_sameToken() public {
    vm.startPrank(GovernanceV3Arbitrum.EXECUTOR_LVL_1);
    vm.expectRevert(ISwapSteward.UnrecognizedTokenSwap.selector);
    steward.setSwappablePair(AaveV3ArbitrumAssets.USDCn_UNDERLYING, AaveV3ArbitrumAssets.USDCn_UNDERLYING, true);
    vm.stopPrank();
  }

  function test_setSwappablePair() public {
    address fromToken = AaveV3ArbitrumAssets.USDCn_UNDERLYING;
    address toToken = AaveV3ArbitrumAssets.ARB_UNDERLYING;

    vm.startPrank(GovernanceV3Arbitrum.EXECUTOR_LVL_1);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.SetSwappablePair(fromToken, toToken, true);
    steward.setSwappablePair(fromToken, toToken, true);

    assertTrue(steward.swapApprovedPair(fromToken, toToken));

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.SetSwappablePair(fromToken, toToken, false);
    steward.setSwappablePair(fromToken, toToken, false);

    assertFalse(steward.swapApprovedPair(fromToken, toToken));
    vm.stopPrank();
  }

  function test_setTokenOracle_revertsIf_notOwner() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.setTokenOracle(AaveV3ArbitrumAssets.USDCn_UNDERLYING, AaveV3ArbitrumAssets.USDCn_ORACLE);
    vm.stopPrank();
  }

  function test_setTokenOracle_revertsIf_zeroAddress() public {
    vm.startPrank(GovernanceV3Arbitrum.EXECUTOR_LVL_1);
    vm.expectRevert(ISwapSteward.InvalidZeroAddress.selector);
    steward.setTokenOracle(AaveV3ArbitrumAssets.USDCn_UNDERLYING, address(0));
    vm.stopPrank();
  }

  function test_setTokenOracle_revertsIf_incompatibleDecimals() public {
    vm.mockCall(
      AaveV3ArbitrumAssets.USDCn_ORACLE, abi.encodeWithSelector(IAggregatorInterface.decimals.selector), abi.encode(18)
    );

    vm.startPrank(GovernanceV3Arbitrum.EXECUTOR_LVL_1);
    vm.expectRevert(ISwapSteward.PriceFeedIncompatibleDecimals.selector);
    steward.setTokenOracle(AaveV3ArbitrumAssets.USDCn_UNDERLYING, AaveV3ArbitrumAssets.USDCn_ORACLE);
    vm.stopPrank();
  }

  function test_setTokenOracle_revertsIf_invalidAnswer() public {
    address mockOracle = address(new MockOracle());

    vm.startPrank(GovernanceV3Arbitrum.EXECUTOR_LVL_1);
    vm.expectRevert(ISwapSteward.PriceFeedInvalidAnswer.selector);
    steward.setTokenOracle(AaveV3ArbitrumAssets.USDCn_UNDERLYING, mockOracle);
    vm.stopPrank();
  }

  function test_setTokenOracle() public {
    address token = AaveV3ArbitrumAssets.USDCn_UNDERLYING;
    address oracle = AaveV3ArbitrumAssets.USDCn_ORACLE;

    vm.startPrank(GovernanceV3Arbitrum.EXECUTOR_LVL_1);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.SetTokenOracle(token, oracle);
    steward.setTokenOracle(token, oracle);

    assertEq(steward.priceOracle(token), oracle);
    vm.stopPrank();
  }

  function test_increaseTokenBudget_revertsIf_notOwner() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.increaseTokenBudget(AaveV3ArbitrumAssets.USDCn_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_increaseTokenBudget() public {
    address token = AaveV3ArbitrumAssets.USDCn_UNDERLYING;
    uint256 amount = 1_000e6;

    vm.startPrank(GovernanceV3Arbitrum.EXECUTOR_LVL_1);

    uint256 budgetBefore = steward.tokenBudget(token);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.UpdatedTokenBudget(token, budgetBefore + amount);
    steward.increaseTokenBudget(token, amount);

    assertEq(steward.tokenBudget(token), budgetBefore + amount);
    vm.stopPrank();
  }

  function test_decreaseTokenBudget_revertsIf_notOwner() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.decreaseTokenBudget(AaveV3ArbitrumAssets.USDCn_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_decreaseTokenBudget_revertsIf_insufficientBudget() public {
    address token = AaveV3ArbitrumAssets.USDCn_UNDERLYING;

    vm.startPrank(GovernanceV3Arbitrum.EXECUTOR_LVL_1);
    vm.expectRevert(ISwapSteward.InsufficientBudget.selector);
    steward.decreaseTokenBudget(token, GUARDIAN_BUDGET + 1);
    vm.stopPrank();
  }

  function test_decreaseTokenBudget() public {
    address token = AaveV3ArbitrumAssets.USDCn_UNDERLYING;
    uint256 decreaseAmount = 10e6;

    vm.startPrank(GovernanceV3Arbitrum.EXECUTOR_LVL_1);

    uint256 budgetBefore = steward.tokenBudget(token);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.UpdatedTokenBudget(token, budgetBefore - decreaseAmount);
    steward.decreaseTokenBudget(token, decreaseAmount);

    assertEq(steward.tokenBudget(token), budgetBefore - decreaseAmount);
    vm.stopPrank();
  }

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

    IConditionalOrder.ConditionalOrderParams memory params =
      _params(fromToken, toToken, SWAP_AMOUNT, uint32(block.timestamp + 1 days));
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
    assertEq(SwapOrder(swapOrder).isValidSignature(orderDigest, signature), IERC1271.isValidSignature.selector);
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

  function test_getExpectedOut_revertsIf_oracleNotSet() public {
    address fromToken = AaveV3ArbitrumAssets.ARB_UNDERLYING;
    address toToken = AaveV3ArbitrumAssets.WETH_UNDERLYING;

    vm.expectRevert(ISwapSteward.OracleNotSet.selector);
    steward.getExpectedOut(1e18, fromToken, toToken);
  }

  function test_getExpectedOut() public {
    address fromToken = AaveV3ArbitrumAssets.USDCn_UNDERLYING;
    address toToken = AaveV3ArbitrumAssets.WETH_UNDERLYING;
    uint256 amount = 100e6;

    uint256 result = steward.getExpectedOut(amount, fromToken, toToken);

    uint256 pFrom = uint256(IAggregatorInterface(AaveV3ArbitrumAssets.USDCn_ORACLE).latestAnswer());
    uint256 pTo = uint256(IAggregatorInterface(AaveV3ArbitrumAssets.WETH_ORACLE).latestAnswer());
    uint256 expected =
      (amount * pFrom * 10 ** IERC20Metadata(toToken).decimals()) / (pTo * 10 ** IERC20Metadata(fromToken).decimals());

    assertEq(result, expected);
  }

  function test_maxRescue() public {
    address token = AaveV3ArbitrumAssets.ARB_UNDERLYING;

    assertEq(steward.maxRescue(token), 0);

    uint256 amount = 1_000e18;
    deal(token, address(steward), amount);

    assertEq(steward.maxRescue(token), amount);
  }

  function test_settle() public {
    address fromToken = AaveV3ArbitrumAssets.USDCn_UNDERLYING;
    address toToken = AaveV3ArbitrumAssets.WETH_UNDERLYING;
    address collector = address(AaveV3Arbitrum.COLLECTOR);
    address swapOrder = _swap(guardian, fromToken, toToken, SWAP_AMOUNT);
    uint32 validUntil = uint32(block.timestamp + 1 days);

    (GPv2Order.Data memory order, bytes memory signature) =
      _getTradeableOrderWithSignature(swapOrder, fromToken, toToken, validUntil);

    uint256 pFrom = uint256(IAggregatorInterface(AaveV3ArbitrumAssets.USDCn_ORACLE).latestAnswer());
    uint256 pTo = uint256(IAggregatorInterface(AaveV3ArbitrumAssets.WETH_ORACLE).latestAnswer());
    uint256 expectedBuyAmount = (SWAP_AMOUNT * pFrom * 10 ** IERC20Metadata(toToken).decimals())
      / (pTo * 10 ** IERC20Metadata(fromToken).decimals()) * (BPS - SWAP_SLIPPAGE) / BPS;
    assertGt(expectedBuyAmount, 0);
    assertEq(order.buyAmount, expectedBuyAmount);

    uint256 collectorBuyBefore = IERC20(toToken).balanceOf(collector);
    deal(toToken, GPV2_SETTLEMENT, order.buyAmount);
    _settle(swapOrder, order, signature);

    assertEq(IERC20(toToken).balanceOf(collector), collectorBuyBefore + expectedBuyAmount);
    assertEq(IERC20(fromToken).balanceOf(swapOrder), 0);
    assertEq(IGPv2SettlementTest(GPV2_SETTLEMENT).filledAmount(_orderUid(swapOrder, order)), SWAP_AMOUNT);
  }

  function test_settle_stableWithinOracleRound() public {
    address fromToken = AaveV3ArbitrumAssets.USDCn_UNDERLYING;
    address toToken = AaveV3ArbitrumAssets.WETH_UNDERLYING;
    address swapOrder = _swap(guardian, fromToken, toToken, SWAP_AMOUNT);
    uint32 validUntil = uint32(block.timestamp + 1 days);

    (GPv2Order.Data memory first, bytes memory firstSignature) =
      _getTradeableOrderWithSignature(swapOrder, fromToken, toToken, validUntil);

    vm.warp(block.timestamp + 1 hours);
    vm.roll(block.number + 1 hours / ARBITRUM_BLOCK_TIME);

    (GPv2Order.Data memory second,) = _getTradeableOrderWithSignature(swapOrder, fromToken, toToken, validUntil);

    bytes32 domainSeparator = IGPv2Settlement(GPV2_SETTLEMENT).domainSeparator();
    assertEq(GPv2Order.hash(first, domainSeparator), GPv2Order.hash(second, domainSeparator));
    assertEq(first.validTo, second.validTo);
    assertEq(_orderUid(swapOrder, first), _orderUid(swapOrder, second));
    deal(address(first.buyToken), GPV2_SETTLEMENT, first.buyAmount);

    _settle(swapOrder, first, firstSignature);
    assertEq(IGPv2SettlementTest(GPV2_SETTLEMENT).filledAmount(_orderUid(swapOrder, first)), SWAP_AMOUNT);
  }

  function test_settle_revertsIf_worseBuyAmount() public {
    address fromToken = AaveV3ArbitrumAssets.USDCn_UNDERLYING;
    address toToken = AaveV3ArbitrumAssets.WETH_UNDERLYING;
    address swapOrder = _swap(guardian, fromToken, toToken, SWAP_AMOUNT);

    (GPv2Order.Data memory order, bytes memory signature) =
      _getTradeableOrderWithSignature(swapOrder, fromToken, toToken, uint32(block.timestamp + 1 days));
    order.buyAmount -= 1;
    deal(address(order.buyToken), GPV2_SETTLEMENT, order.buyAmount);
    vm.expectRevert(ERC1271Forwarder.InvalidHash.selector);
    _settle(swapOrder, order, signature);
  }

  function test_settle_revertsIf_afterOracleRoundChange() public {
    address fromToken = AaveV3ArbitrumAssets.USDCn_UNDERLYING;
    address toToken = AaveV3ArbitrumAssets.WETH_UNDERLYING;
    address swapOrder = _swap(guardian, fromToken, toToken, SWAP_AMOUNT);
    uint32 validUntil = uint32(block.timestamp + 1 days);

    (GPv2Order.Data memory order, bytes memory signature) =
      _getTradeableOrderWithSignature(swapOrder, fromToken, toToken, validUntil);

    int256 currentAnswer = IAggregatorInterface(AaveV3ArbitrumAssets.WETH_ORACLE).latestAnswer();
    vm.mockCall(
      AaveV3ArbitrumAssets.WETH_ORACLE,
      abi.encodeWithSelector(IAggregatorInterface.latestAnswer.selector),
      abi.encode(currentAnswer * int256(BPS + ORACLE_MOVE_BPS) / int256(BPS))
    );

    (GPv2Order.Data memory refreshed,) = _getTradeableOrderWithSignature(swapOrder, fromToken, toToken, validUntil);
    assertNotEq(refreshed.buyAmount, order.buyAmount);
    deal(address(refreshed.buyToken), GPV2_SETTLEMENT, refreshed.buyAmount);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, INVALID_HASH));
    _settle(swapOrder, order, signature);
  }

  function test_settle_revertsIf_expired() public {
    address fromToken = AaveV3ArbitrumAssets.USDCn_UNDERLYING;
    address toToken = AaveV3ArbitrumAssets.WETH_UNDERLYING;
    address swapOrder = _swap(guardian, fromToken, toToken, SWAP_AMOUNT);
    uint32 validUntil = uint32(block.timestamp + 1 days);

    (GPv2Order.Data memory order, bytes memory signature) =
      _getTradeableOrderWithSignature(swapOrder, fromToken, toToken, validUntil);

    vm.warp(uint256(validUntil) + 1);

    IConditionalOrder.ConditionalOrderParams memory params = _params(fromToken, toToken, SWAP_AMOUNT, validUntil);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, ORDER_EXPIRED));
    IComposableCow(COMPOSABLE_COW).getTradeableOrderWithSignature(swapOrder, params, "", new bytes32[](0));
    deal(address(order.buyToken), GPV2_SETTLEMENT, order.buyAmount);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, ORDER_EXPIRED));
    _settle(swapOrder, order, signature);
  }

  function _params(address fromToken, address toToken, uint256 amount, uint32 validUntil)
    internal
    view
    returns (IConditionalOrder.ConditionalOrderParams memory)
  {
    return IConditionalOrder.ConditionalOrderParams(
      IConditionalOrder(address(marketOrderHandler)),
      bytes32(0),
      abi.encode(
        OracleMarketOrder.Data({
          fromToken: fromToken,
          toToken: toToken,
          fromOracle: steward.priceOracle(fromToken),
          toOracle: steward.priceOracle(toToken),
          receiver: address(AaveV3Arbitrum.COLLECTOR),
          sellAmount: amount,
          slippage: SWAP_SLIPPAGE,
          appData: APP_DATA,
          validUntil: validUntil,
          sequencerUptimeFeed: ChainlinkArbitrum.L2_Sequencer_Uptime_Status_Feed,
          sequencerGracePeriod: steward.SEQUENCER_GRACE_PERIOD()
        })
      )
    );
  }

  function _getTradeableOrderWithSignature(address owner, address fromToken, address toToken, uint32 validUntil)
    internal
    view
    returns (GPv2Order.Data memory, bytes memory)
  {
    return IComposableCow(COMPOSABLE_COW)
      .getTradeableOrderWithSignature(owner, _params(fromToken, toToken, SWAP_AMOUNT, validUntil), "", new bytes32[](0));
  }

  /// @dev GPv2Settlement exposes no UID getter; `filledAmount` is keyed by the packed UID (digest, owner, validTo).
  /// https://github.com/cowprotocol/contracts/blob/a10f40788af29467e87de3dbf2196662b0a6b500/src/contracts/libraries/GPv2Order.sol#L167-L212
  function _orderUid(address owner, GPv2Order.Data memory order) internal view returns (bytes memory orderUid) {
    orderUid = new bytes(GPv2Order.UID_LENGTH);
    GPv2Order.packOrderUidParams(
      orderUid, GPv2Order.hash(order, IGPv2Settlement(GPV2_SETTLEMENT).domainSeparator()), owner, order.validTo
    );
  }

  function _settle(address owner, GPv2Order.Data memory order, bytes memory signature) internal {
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = order.sellToken;
    tokens[1] = order.buyToken;

    uint256[] memory clearingPrices = new uint256[](2);
    clearingPrices[0] = order.buyAmount;
    clearingPrices[1] = order.sellAmount;

    GPv2TradeData[] memory trades = new GPv2TradeData[](1);
    trades[0] = GPv2TradeData({
      sellTokenIndex: 0,
      buyTokenIndex: 1,
      receiver: order.receiver,
      sellAmount: order.sellAmount,
      buyAmount: order.buyAmount,
      validTo: order.validTo,
      appData: order.appData,
      feeAmount: order.feeAmount,
      flags: FLAGS_SELL_FILL_OR_KILL_EIP1271,
      executedAmount: 0,
      signature: abi.encodePacked(owner, signature)
    });

    // pre, intra and post-settlement interactions; all empty because the settlement already holds the buy tokens
    GPv2InteractionData[][3] memory interactions;

    vm.prank(solver);
    IGPv2SettlementTest(GPV2_SETTLEMENT).settle(tokens, clearingPrices, trades, interactions);
  }

  function _swap(address caller, address fromToken, address toToken, uint256 amount) internal returns (address) {
    address swapOrder = vm.computeCreateAddress(address(steward), vm.getNonce(address(steward)));
    vm.prank(caller);
    steward.swap(fromToken, toToken, amount, SWAP_SLIPPAGE);
    return swapOrder;
  }
}

