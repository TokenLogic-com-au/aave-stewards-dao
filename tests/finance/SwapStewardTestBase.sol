// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC1271} from "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {IGPv2Settlement} from "src/finance/interfaces/IGPv2Settlement.sol";
import {IAggregatorInterface} from "src/finance/interfaces/IAggregatorInterface.sol";
import {IComposableCow} from "src/finance/interfaces/IComposableCow.sol";
import {IConditionalOrder} from "src/finance/interfaces/IConditionalOrder.sol";
import {GPv2Order} from "src/finance/libraries/GPv2Order.sol";
import {
  TWAPOrder,
  INVALID_TOKEN,
  INVALID_MIN_PART_LIMIT,
  INVALID_START_TIME,
  INVALID_NUM_PARTS,
  INVALID_FREQUENCY,
  INVALID_SPAN
} from "src/finance/libraries/TWAPOrder.sol";
import {OracleMarketOrder} from "src/finance/OracleMarketOrder.sol";
import {INVALID_HASH} from "src/finance/BaseConditionalOrder.sol";
import {ERC1271Forwarder} from "src/finance/ERC1271Forwarder.sol";
import {ISwapSteward} from "src/finance/interfaces/ISwapSteward.sol";
import {SwapEscrow} from "src/finance/SwapEscrow.sol";
import {SwapSteward} from "src/finance/SwapSteward.sol";
import {MockAggregator} from "tests/finance/OracleMocks.sol";

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
 * command: forge test -vvv --match-path 'tests/finance/SwapSteward*.t.sol'
 */
abstract contract SwapStewardTestBase is Test {
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
    address otherToken;
    address otherOracle;
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

  bytes32 internal constant APP_DATA = bytes32(0);
  bytes32 internal constant FUNDS_ADMIN_ROLE = bytes32("FUNDS_ADMIN");
  uint256 internal constant BPS = 100_00;
  uint256 internal constant SWAP_SLIPPAGE = 50;
  uint256 internal constant MAX_SLIPPAGE = 10_00;
  uint256 internal constant ORACLE_MOVE_BPS = 100;
  uint256 internal constant TWAP_NUM_PARTS = 4;
  uint256 internal constant TWAP_PART_DURATION = 1 hours;
  uint256 internal constant TWAP_SPAN = 30 minutes;
  uint256 internal constant TWAP_MAX_PART_DURATION = 365 days;
  /// @dev Handler reasons of composable-cow c0435953, src/types/twap/{TWAP.sol,libraries/TWAPOrderMathLib.sol}
  string internal constant TWAP_BEFORE_START = "before twap start";
  string internal constant TWAP_AFTER_FINISH = "after twap finish";
  string internal constant TWAP_NOT_WITHIN_SPAN = "not within span";
  string internal constant GPV2_ORDER_FILLED = "GPv2: order filled";
  /// @dev GPv2Trade flags: bits 0-4 = 0 (sell, fill-or-kill, ERC20 sell and buy balances); bits 5-6 = signing
  /// scheme, where GPv2Signing.Scheme.Eip1271 = 2.
  /// https://github.com/cowprotocol/contracts/blob/a10f40788af29467e87de3dbf2196662b0a6b500/src/contracts/libraries/GPv2Trade.sol#L58-L131
  /// https://github.com/cowprotocol/contracts/blob/a10f40788af29467e87de3dbf2196662b0a6b500/src/contracts/mixins/GPv2Signing.sol#L24-L29
  uint256 internal constant FLAGS_SELL_FILL_OR_KILL_EIP1271 = 2 << 5;

  address public guardian = makeAddr("guardian");
  address public alice = makeAddr("alice");
  address public solver = makeAddr("solver");

  OracleMarketOrder public marketOrderHandler;
  SwapSteward public steward;
  ChainConfig internal cfg;

  function _config() internal view virtual returns (ChainConfig memory);

  function setUp() public {
    cfg = _config();
    vm.createSelectFork(vm.rpcUrl(cfg.rpcAlias), cfg.forkBlock);

    marketOrderHandler = new OracleMarketOrder();
    steward = new SwapSteward(
      cfg.executor,
      guardian,
      cfg.collector,
      COMPOSABLE_COW,
      address(marketOrderHandler),
      TWAP_HANDLER,
      VAULT_RELAYER,
      cfg.sequencerUptimeFeed
    );

    vm.startPrank(cfg.executor);
    IAccessControl(cfg.collector).grantRole(FUNDS_ADMIN_ROLE, address(steward));
    steward.setSwappablePair(cfg.fromToken, cfg.toToken, true);
    steward.setTokenOracle(cfg.fromToken, cfg.fromOracle);
    steward.setTokenOracle(cfg.toToken, cfg.toOracle);
    steward.increaseTokenBudget(cfg.fromToken, cfg.guardianBudget);
    vm.stopPrank();

    address authenticator = IGPv2SettlementTest(GPV2_SETTLEMENT).authenticator();
    vm.prank(IGPv2AllowListAuthentication(authenticator).manager());
    IGPv2AllowListAuthentication(authenticator).addSolver(solver);
  }

  function test_constructor_revertsWith_InvalidZeroAddress() public {
    for (uint256 i; i < 5; ++i) {
      address[5] memory a = [cfg.collector, COMPOSABLE_COW, address(marketOrderHandler), TWAP_HANDLER, VAULT_RELAYER];
      a[i] = address(0);
      vm.expectRevert(ISwapSteward.InvalidZeroAddress.selector);
      this.createSteward(a[0], a[1], a[2], a[3], a[4]);
    }
  }

  function test_constructor_allowsZeroGuardianAndSequencerFeed() public {
    SwapSteward stewardZeroGuardian = new SwapSteward(
      cfg.executor,
      address(0),
      cfg.collector,
      COMPOSABLE_COW,
      address(marketOrderHandler),
      TWAP_HANDLER,
      VAULT_RELAYER,
      address(0)
    );
    assertEq(stewardZeroGuardian.guardian(), address(0));
    assertEq(stewardZeroGuardian.SEQUENCER_UPTIME_FEED(), address(0));
  }

  function test_rescueToken_revertsWith_OnlyGuardianOrOwnerInvalidCaller_fullBalance() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.rescueToken(cfg.otherToken);
  }

  function test_rescueToken_revertsWith_OnlyGuardianOrOwnerInvalidCaller_amount() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.rescueToken(cfg.otherToken, 1);
  }

  function test_rescueToken() public {
    address collector = cfg.collector;
    address token = cfg.otherToken;
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
    address collector = cfg.collector;
    address token = cfg.otherToken;
    uint256 amount = 1_000e18;
    uint256 rescueAmount = 500e18;

    deal(token, address(steward), amount);
    uint256 collectorBefore = IERC20(token).balanceOf(collector);

    vm.prank(guardian);
    steward.rescueToken(token, rescueAmount);

    assertEq(IERC20(token).balanceOf(address(steward)), amount - rescueAmount);
    assertEq(IERC20(token).balanceOf(collector), collectorBefore + rescueAmount);
  }

  function test_setSwappablePair_revertsWith_OwnableUnauthorizedAccount() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.setSwappablePair(cfg.fromToken, cfg.otherToken, true);
    vm.stopPrank();
  }

  function test_setSwappablePair_revertsWith_UnrecognizedTokenSwap() public {
    vm.startPrank(cfg.executor);
    vm.expectRevert(ISwapSteward.UnrecognizedTokenSwap.selector);
    steward.setSwappablePair(cfg.fromToken, cfg.fromToken, true);
    vm.stopPrank();
  }

  function test_setSwappablePair() public {
    address fromToken = cfg.fromToken;
    address toToken = cfg.otherToken;

    vm.startPrank(cfg.executor);

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

  function test_setTokenOracle_revertsWith_OwnableUnauthorizedAccount() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.setTokenOracle(cfg.fromToken, cfg.fromOracle);
    vm.stopPrank();
  }

  function test_setTokenOracle_revertsWith_InvalidZeroAddress() public {
    vm.startPrank(cfg.executor);
    vm.expectRevert(ISwapSteward.InvalidZeroAddress.selector);
    steward.setTokenOracle(cfg.fromToken, address(0));
    vm.stopPrank();
  }

  function test_setTokenOracle_revertsWith_PriceFeedIncompatibleDecimals() public {
    vm.mockCall(cfg.fromOracle, abi.encodeWithSelector(IAggregatorInterface.decimals.selector), abi.encode(18));

    vm.startPrank(cfg.executor);
    vm.expectRevert(ISwapSteward.PriceFeedIncompatibleDecimals.selector);
    steward.setTokenOracle(cfg.fromToken, cfg.fromOracle);
    vm.stopPrank();
  }

  function test_setTokenOracle_revertsWith_PriceFeedInvalidAnswer() public {
    int256[2] memory badAnswers = [int256(0), int256(-1)];

    for (uint256 i; i < badAnswers.length; i++) {
      address mockOracle = address(new MockAggregator(badAnswers[i]));

      vm.prank(cfg.executor);
      vm.expectRevert(ISwapSteward.PriceFeedInvalidAnswer.selector);
      steward.setTokenOracle(cfg.fromToken, mockOracle);
    }
  }

  function test_setTokenOracle() public {
    address newToken = cfg.otherToken;
    address newOracle = cfg.otherOracle;
    address replacedToken = cfg.fromToken;
    address replacementOracle = cfg.toOracle;

    assertEq(steward.priceOracle(newToken), address(0));
    assertEq(steward.priceOracle(replacedToken), cfg.fromOracle);

    vm.startPrank(cfg.executor);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.SetTokenOracle(newToken, newOracle);
    steward.setTokenOracle(newToken, newOracle);
    assertEq(steward.priceOracle(newToken), newOracle);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.SetTokenOracle(replacedToken, replacementOracle);
    steward.setTokenOracle(replacedToken, replacementOracle);
    assertEq(steward.priceOracle(replacedToken), replacementOracle);
    vm.stopPrank();
  }

  function test_increaseTokenBudget_revertsWith_OwnableUnauthorizedAccount() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.increaseTokenBudget(cfg.fromToken, 100 * cfg.swapAmount);
    vm.stopPrank();
  }

  function test_increaseTokenBudget() public {
    address token = cfg.fromToken;
    uint256 amount = 100 * cfg.swapAmount;

    vm.startPrank(cfg.executor);

    uint256 budgetBefore = steward.tokenBudget(token);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.UpdatedTokenBudget(token, budgetBefore + amount);
    steward.increaseTokenBudget(token, amount);

    assertEq(steward.tokenBudget(token), budgetBefore + amount);
    vm.stopPrank();
  }

  function test_decreaseTokenBudget_revertsWith_OwnableUnauthorizedAccount() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.decreaseTokenBudget(cfg.fromToken, 100 * cfg.swapAmount);
    vm.stopPrank();
  }

  function test_decreaseTokenBudget_revertsWith_InsufficientBudget() public {
    address token = cfg.fromToken;

    vm.startPrank(cfg.executor);
    vm.expectRevert(ISwapSteward.InsufficientBudget.selector);
    steward.decreaseTokenBudget(token, cfg.guardianBudget + 1);
    vm.stopPrank();
  }

  function test_decreaseTokenBudget() public {
    address token = cfg.fromToken;
    uint256 decreaseAmount = cfg.swapAmount;

    vm.startPrank(cfg.executor);

    uint256 budgetBefore = steward.tokenBudget(token);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.UpdatedTokenBudget(token, budgetBefore - decreaseAmount);
    steward.decreaseTokenBudget(token, decreaseAmount);

    assertEq(steward.tokenBudget(token), budgetBefore - decreaseAmount);
    vm.stopPrank();
  }

  function test_swap_revertsWith_OnlyGuardianOrOwnerInvalidCaller() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.swap(cfg.fromToken, cfg.toToken, cfg.swapAmount, SWAP_SLIPPAGE);
  }

  function test_swap_revertsWith_InvalidZeroAmount() public {
    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.InvalidZeroAmount.selector);
    steward.swap(cfg.fromToken, cfg.toToken, 0, SWAP_SLIPPAGE);
  }

  function test_swap_revertsWith_UnrecognizedTokenSwap_pairNotApproved() public {
    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.UnrecognizedTokenSwap.selector);
    steward.swap(cfg.fromToken, cfg.otherToken, cfg.swapAmount, SWAP_SLIPPAGE);
  }

  function test_swap_revertsWith_UnrecognizedTokenSwap_reversedPair() public {
    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.UnrecognizedTokenSwap.selector);
    steward.swap(cfg.toToken, cfg.fromToken, cfg.swapAmount, SWAP_SLIPPAGE);
  }

  function test_swap_revertsWith_OracleNotSet_fromOracleUnset() public {
    _approvePairsWithOtherToken();

    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.OracleNotSet.selector);
    steward.swap(cfg.otherToken, cfg.fromToken, cfg.swapAmount, SWAP_SLIPPAGE);
  }

  function test_swap_revertsWith_OracleNotSet_toOracleUnset() public {
    _approvePairsWithOtherToken();

    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.OracleNotSet.selector);
    steward.swap(cfg.fromToken, cfg.otherToken, cfg.swapAmount, SWAP_SLIPPAGE);
  }

  function test_swap_revertsWith_InvalidSlippage() public {
    address fromToken = cfg.fromToken;
    address toToken = cfg.toToken;

    vm.startPrank(guardian);
    steward.swap(fromToken, toToken, cfg.swapAmount, MAX_SLIPPAGE);

    vm.expectRevert(ISwapSteward.InvalidSlippage.selector);
    steward.swap(fromToken, toToken, cfg.swapAmount, MAX_SLIPPAGE + 1);
    vm.stopPrank();
  }

  function test_swap_revertsWith_PriceFeedInvalidAnswer() public {
    address fromToken = cfg.fromToken;
    address toToken = cfg.toToken;
    int256[2] memory badAnswers = [int256(0), int256(-1)];
    address[2] memory oracles = [cfg.fromOracle, cfg.toOracle];

    for (uint256 i; i < oracles.length; i++) {
      for (uint256 j; j < badAnswers.length; j++) {
        vm.mockCall(
          oracles[i], abi.encodeWithSelector(IAggregatorInterface.latestAnswer.selector), abi.encode(badAnswers[j])
        );
        vm.prank(guardian);
        vm.expectRevert(ISwapSteward.PriceFeedInvalidAnswer.selector);
        steward.swap(fromToken, toToken, cfg.swapAmount, SWAP_SLIPPAGE);
        vm.clearMockedCalls();
      }
    }
  }

  function test_swap_revertsWith_InsufficientBudget() public {
    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.InsufficientBudget.selector);
    steward.swap(cfg.fromToken, cfg.toToken, cfg.guardianBudget + 1, SWAP_SLIPPAGE);
  }

  function test_swap_ownerSkipsBudget() public {
    address fromToken = cfg.fromToken;
    uint256 amount = cfg.guardianBudget + cfg.swapAmount / 10;

    address escrow = _swap(cfg.executor, fromToken, cfg.toToken, amount);

    assertEq(steward.tokenBudget(fromToken), cfg.guardianBudget);
    assertEq(IERC20(fromToken).balanceOf(escrow), amount);
  }

  function test_swap_maxAmount() public {
    address fromToken = cfg.fromToken;
    address toToken = cfg.toToken;
    address collector = cfg.collector;

    uint32 validUntil = uint32(block.timestamp + 1 days);

    address guardianEscrow = _swap(guardian, fromToken, toToken, type(uint256).max);
    assertEq(IERC20(fromToken).balanceOf(guardianEscrow), cfg.guardianBudget);
    assertEq(steward.tokenBudget(fromToken), 0);
    (, bytes32 guardianHash) = steward.swaps(guardianEscrow);
    assertEq(
      guardianHash,
      keccak256(abi.encode(_marketParams(_marketData(fromToken, toToken, cfg.guardianBudget, validUntil))))
    );

    uint256 collectorBalance = IERC20(fromToken).balanceOf(collector);
    address ownerEscrow = _swap(cfg.executor, fromToken, toToken, type(uint256).max);
    assertEq(IERC20(fromToken).balanceOf(ownerEscrow), collectorBalance);
    assertEq(IERC20(fromToken).balanceOf(collector), 0);
    (, bytes32 ownerHash) = steward.swaps(ownerEscrow);
    assertEq(
      ownerHash, keccak256(abi.encode(_marketParams(_marketData(fromToken, toToken, collectorBalance, validUntil))))
    );
  }

  function test_swap() public {
    address fromToken = cfg.fromToken;
    address toToken = cfg.toToken;
    address collector = cfg.collector;
    uint256 collectorBalanceBefore = IERC20(fromToken).balanceOf(collector);
    assertGe(collectorBalanceBefore, cfg.swapAmount);

    address expectedEscrow = vm.computeCreateAddress(address(steward), vm.getNonce(address(steward)));
    IConditionalOrder.ConditionalOrderParams memory params =
      _marketParams(_marketData(fromToken, toToken, cfg.swapAmount, uint32(block.timestamp + 1 days)));

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.SwapRequested(
      expectedEscrow,
      keccak256(abi.encode(params)),
      fromToken,
      toToken,
      cfg.fromOracle,
      cfg.toOracle,
      cfg.swapAmount,
      SWAP_SLIPPAGE
    );
    address escrow = _swap(guardian, fromToken, toToken, cfg.swapAmount);
    (address swapFromToken, bytes32 orderHash) = steward.swaps(escrow);

    assertEq(swapFromToken, fromToken);
    assertTrue(IComposableCow(COMPOSABLE_COW).singleOrders(escrow, orderHash));
    assertEq(IERC20(fromToken).balanceOf(escrow), cfg.swapAmount);
    assertEq(IERC20(fromToken).balanceOf(address(steward)), 0);
    assertEq(IERC20(fromToken).balanceOf(collector), collectorBalanceBefore - cfg.swapAmount);
    assertEq(IERC20(fromToken).allowance(escrow, VAULT_RELAYER), cfg.swapAmount);
    assertEq(steward.tokenBudget(fromToken), cfg.guardianBudget - cfg.swapAmount);

    assertEq(keccak256(abi.encode(params)), orderHash);

    (GPv2Order.Data memory order, bytes memory signature) =
      IComposableCow(COMPOSABLE_COW).getTradeableOrderWithSignature(escrow, params, "", new bytes32[](0));

    uint256 expectedBuyAmount = _expectedOut(cfg.swapAmount) * (BPS - SWAP_SLIPPAGE) / BPS;

    assertEq(address(order.sellToken), fromToken);
    assertEq(address(order.buyToken), toToken);
    assertEq(order.receiver, collector);
    assertEq(order.sellAmount, cfg.swapAmount);
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
    assertEq(SwapEscrow(escrow).isValidSignature(orderDigest, signature), IERC1271.isValidSignature.selector);
  }

  function test_swap_twoSwapsSameFromToken() public {
    address fromToken = cfg.fromToken;
    address toToken = cfg.toToken;

    address first = _swap(guardian, fromToken, toToken, cfg.swapAmount);
    address second = _swap(guardian, fromToken, toToken, 2 * cfg.swapAmount);

    assertNotEq(first, second);
    assertEq(IERC20(fromToken).balanceOf(first), cfg.swapAmount);
    assertEq(IERC20(fromToken).balanceOf(second), 2 * cfg.swapAmount);
    assertEq(IERC20(fromToken).allowance(first, VAULT_RELAYER), cfg.swapAmount);
    assertEq(IERC20(fromToken).allowance(second, VAULT_RELAYER), 2 * cfg.swapAmount);

    (, bytes32 firstHash) = steward.swaps(first);
    (, bytes32 secondHash) = steward.swaps(second);
    assertTrue(IComposableCow(COMPOSABLE_COW).singleOrders(first, firstHash));
    assertTrue(IComposableCow(COMPOSABLE_COW).singleOrders(second, secondHash));
  }

  function test_cancelSwap_revertsWith_OnlyGuardianOrOwnerInvalidCaller() public {
    address fromToken = cfg.fromToken;
    address escrow = _swap(guardian, fromToken, cfg.toToken, cfg.swapAmount);
    (address swapFromToken, bytes32 orderHash) = steward.swaps(escrow);

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.cancelSwap(escrow);

    (address fromTokenAfter, bytes32 orderHashAfter) = steward.swaps(escrow);
    assertEq(fromTokenAfter, swapFromToken);
    assertEq(orderHashAfter, orderHash);
    assertTrue(IComposableCow(COMPOSABLE_COW).singleOrders(escrow, orderHash));
    assertEq(IERC20(fromToken).balanceOf(escrow), cfg.swapAmount);
    assertEq(IERC20(fromToken).allowance(escrow, VAULT_RELAYER), cfg.swapAmount);
  }

  function test_cancelSwap_revertsWith_SwapNotFound() public {
    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.SwapNotFound.selector);
    steward.cancelSwap(alice);
  }

  function test_cancelSwap() public {
    address fromToken = cfg.fromToken;
    address collector = cfg.collector;
    uint256 collectorBalanceBefore = IERC20(fromToken).balanceOf(collector);

    address escrow = _swap(guardian, fromToken, cfg.toToken, cfg.swapAmount);
    (, bytes32 orderHash) = steward.swaps(escrow);

    vm.expectEmit(address(steward));
    emit ISwapSteward.SwapCanceled(escrow, orderHash, fromToken, cfg.swapAmount);
    vm.prank(guardian);
    steward.cancelSwap(escrow);

    (address swapFromToken, bytes32 swapHash) = steward.swaps(escrow);
    assertEq(swapFromToken, address(0));
    assertEq(swapHash, bytes32(0));
    assertFalse(IComposableCow(COMPOSABLE_COW).singleOrders(escrow, orderHash));
    assertEq(IERC20(fromToken).allowance(escrow, VAULT_RELAYER), 0);
    assertEq(IERC20(fromToken).balanceOf(escrow), 0);
    assertEq(IERC20(fromToken).balanceOf(collector), collectorBalanceBefore);

    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.SwapNotFound.selector);
    steward.cancelSwap(escrow);
  }

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
    data.buyToken = IERC20(cfg.otherToken);

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
    data.partSellAmount = cfg.guardianBudget / TWAP_NUM_PARTS + 1;

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
    vm.prank(cfg.executor);
    steward.setSwappablePair(cfg.fromToken, address(0), true);

    TWAPOrder.Data memory data = _twapData(0, 0);
    data.buyToken = IERC20(address(0));

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
    address fromToken = cfg.fromToken;
    deal(fromToken, cfg.collector, uint256(type(uint32).max) + 2 * cfg.twapPartAmount);

    TWAPOrder.Data memory twoParts = _twapData(block.timestamp, TWAP_MAX_PART_DURATION);
    twoParts.n = 2;
    twoParts.t = TWAP_MAX_PART_DURATION;
    address twoPartsEscrow = _twapSwap(guardian, twoParts);
    (, bytes32 twoPartsHash) = steward.swaps(twoPartsEscrow);
    assertEq(twoPartsHash, keccak256(abi.encode(_twapParams(twoParts))));

    TWAPOrder.Data memory maxParts = _twapData(block.timestamp, 0);
    maxParts.partSellAmount = 1;
    maxParts.n = type(uint32).max;
    address maxPartsEscrow = _twapSwap(cfg.executor, maxParts);
    (, bytes32 maxPartsHash) = steward.swaps(maxPartsEscrow);
    assertEq(maxPartsHash, keccak256(abi.encode(_twapParams(maxParts))));
    assertEq(IERC20(fromToken).balanceOf(maxPartsEscrow), type(uint32).max);
  }

  function test_twapSwap() public {
    address fromToken = cfg.fromToken;
    address toToken = cfg.toToken;
    address collector = cfg.collector;
    uint256 total = cfg.twapPartAmount * TWAP_NUM_PARTS;
    uint256 collectorBalanceBefore = IERC20(fromToken).balanceOf(collector);

    TWAPOrder.Data memory data = _twapData(block.timestamp + TWAP_PART_DURATION, 0);
    IConditionalOrder.ConditionalOrderParams memory params = _twapParams(data);
    bytes32 expectedHash = keccak256(abi.encode(params));

    address expectedEscrow = vm.computeCreateAddress(address(steward), vm.getNonce(address(steward)));

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.TWAPSwapRequested(expectedEscrow, expectedHash, fromToken, toToken, total);
    address escrow = _twapSwap(guardian, data);
    assertEq(escrow, expectedEscrow);

    (address swapFromToken, bytes32 orderHash) = steward.swaps(escrow);
    assertEq(swapFromToken, fromToken);
    assertEq(orderHash, expectedHash);
    assertTrue(IComposableCow(COMPOSABLE_COW).singleOrders(escrow, expectedHash));
    assertEq(IERC20(fromToken).balanceOf(escrow), total);
    assertEq(IERC20(fromToken).balanceOf(address(steward)), 0);
    assertEq(IERC20(fromToken).balanceOf(collector), collectorBalanceBefore - total);
    assertEq(IERC20(fromToken).allowance(escrow, VAULT_RELAYER), total);
    assertEq(steward.tokenBudget(fromToken), cfg.guardianBudget - total);

    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, TWAP_BEFORE_START));
    IComposableCow(COMPOSABLE_COW).getTradeableOrderWithSignature(escrow, params, "", new bytes32[](0));
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
    address fromToken = cfg.fromToken;
    TWAPOrder.Data memory data = _twapData(0, 0);
    data.partSellAmount = cfg.guardianBudget / TWAP_NUM_PARTS + cfg.swapAmount / 10;
    uint256 total = data.partSellAmount * TWAP_NUM_PARTS;
    assertGt(total, cfg.guardianBudget);

    address escrow = _twapSwap(cfg.executor, data);

    assertEq(steward.tokenBudget(fromToken), cfg.guardianBudget);
    assertEq(IERC20(fromToken).balanceOf(escrow), total);
  }

  function test_twapSwap_settleParts() public {
    address toToken = cfg.toToken;
    address collector = cfg.collector;
    uint256 t0 = block.timestamp;
    address escrow = _twapSwap(guardian, _twapData(0, 0));
    uint256 collectorBuyBefore = IERC20(toToken).balanceOf(collector);

    (GPv2Order.Data memory first, bytes memory firstSignature) = _getTwapOrderWithSignature(escrow, t0, 0);

    assertEq(address(first.sellToken), cfg.fromToken);
    assertEq(address(first.buyToken), toToken);
    assertEq(first.receiver, collector);
    assertEq(first.sellAmount, cfg.twapPartAmount);
    assertEq(first.buyAmount, cfg.twapMinPartLimit);
    assertEq(first.validTo, t0 + TWAP_PART_DURATION - 1);
    assertEq(first.appData, APP_DATA);
    assertEq(first.feeAmount, 0);
    assertEq(first.kind, GPv2Order.KIND_SELL);
    assertFalse(first.partiallyFillable);
    assertEq(first.sellTokenBalance, GPv2Order.BALANCE_ERC20);
    assertEq(first.buyTokenBalance, GPv2Order.BALANCE_ERC20);

    deal(toToken, GPV2_SETTLEMENT, first.buyAmount);
    _settle(escrow, first, firstSignature);

    assertEq(IERC20(toToken).balanceOf(collector), collectorBuyBefore + cfg.twapMinPartLimit);
    assertEq(IGPv2SettlementTest(GPV2_SETTLEMENT).filledAmount(_orderUid(escrow, first)), cfg.twapPartAmount);
    assertEq(IERC20(first.sellToken).balanceOf(escrow), cfg.twapPartAmount * (TWAP_NUM_PARTS - 1));
    assertEq(IERC20(first.sellToken).allowance(escrow, VAULT_RELAYER), cfg.twapPartAmount * (TWAP_NUM_PARTS - 1));

    vm.expectRevert(abi.encodeWithSignature("Error(string)", GPV2_ORDER_FILLED));
    _settle(escrow, first, firstSignature);

    vm.warp(t0 + TWAP_PART_DURATION);
    (GPv2Order.Data memory second, bytes memory secondSignature) = _getTwapOrderWithSignature(escrow, t0, 0);

    assertEq(second.validTo, t0 + 2 * TWAP_PART_DURATION - 1);
    assertNotEq(_orderUid(escrow, second), _orderUid(escrow, first));

    deal(toToken, GPV2_SETTLEMENT, second.buyAmount);
    _settle(escrow, second, secondSignature);

    assertEq(IERC20(toToken).balanceOf(collector), collectorBuyBefore + 2 * cfg.twapMinPartLimit);
    assertEq(IGPv2SettlementTest(GPV2_SETTLEMENT).filledAmount(_orderUid(escrow, second)), cfg.twapPartAmount);
    assertEq(IERC20(first.sellToken).balanceOf(escrow), cfg.twapPartAmount * (TWAP_NUM_PARTS - 2));
  }

  function test_twapSwap_span() public {
    uint256 t0 = block.timestamp;
    address escrow = _twapSwap(guardian, _twapData(0, TWAP_SPAN));

    (GPv2Order.Data memory first,) = _getTwapOrderWithSignature(escrow, t0, TWAP_SPAN);
    assertEq(first.validTo, t0 + TWAP_SPAN - 1);

    vm.warp(t0 + TWAP_SPAN);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, TWAP_NOT_WITHIN_SPAN));
    _getTwapOrderWithSignature(escrow, t0, TWAP_SPAN);

    vm.warp(t0 + TWAP_PART_DURATION);
    (GPv2Order.Data memory second,) = _getTwapOrderWithSignature(escrow, t0, TWAP_SPAN);
    assertEq(second.validTo, t0 + TWAP_PART_DURATION + TWAP_SPAN - 1);
  }

  function test_twapSwap_cancelAfterPart() public {
    address fromToken = cfg.fromToken;
    address toToken = cfg.toToken;
    address collector = cfg.collector;
    uint256 t0 = block.timestamp;
    uint256 collectorSellBefore = IERC20(fromToken).balanceOf(collector);
    address escrow = _twapSwap(guardian, _twapData(0, 0));
    (, bytes32 orderHash) = steward.swaps(escrow);

    (GPv2Order.Data memory first, bytes memory signature) = _getTwapOrderWithSignature(escrow, t0, 0);
    deal(toToken, GPV2_SETTLEMENT, first.buyAmount);
    _settle(escrow, first, signature);

    uint256 remainder = cfg.twapPartAmount * (TWAP_NUM_PARTS - 1);
    vm.expectEmit(address(steward));
    emit ISwapSteward.SwapCanceled(escrow, orderHash, fromToken, remainder);
    vm.prank(guardian);
    steward.cancelSwap(escrow);

    (address swapFromToken, bytes32 swapHash) = steward.swaps(escrow);
    assertEq(swapFromToken, address(0));
    assertEq(swapHash, bytes32(0));
    assertFalse(IComposableCow(COMPOSABLE_COW).singleOrders(escrow, orderHash));
    assertEq(IERC20(fromToken).allowance(escrow, VAULT_RELAYER), 0);
    assertEq(IERC20(fromToken).balanceOf(escrow), 0);
    assertEq(IERC20(fromToken).balanceOf(collector), collectorSellBefore - cfg.twapPartAmount);
  }

  function test_twapSwap_afterFinish() public {
    address fromToken = cfg.fromToken;
    address toToken = cfg.toToken;
    address collector = cfg.collector;
    uint256 t0 = block.timestamp;
    uint256 collectorSellBefore = IERC20(fromToken).balanceOf(collector);
    address escrow = _twapSwap(guardian, _twapData(0, 0));

    (GPv2Order.Data memory first, bytes memory signature) = _getTwapOrderWithSignature(escrow, t0, 0);
    deal(toToken, GPV2_SETTLEMENT, first.buyAmount);
    _settle(escrow, first, signature);

    uint256 finish = t0 + TWAP_NUM_PARTS * TWAP_PART_DURATION;
    vm.warp(finish - 1);
    (GPv2Order.Data memory last,) = _getTwapOrderWithSignature(escrow, t0, 0);
    assertEq(last.validTo, finish - 1);

    vm.warp(finish);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, TWAP_AFTER_FINISH));
    _getTwapOrderWithSignature(escrow, t0, 0);

    vm.prank(guardian);
    steward.cancelSwap(escrow);

    assertEq(IERC20(fromToken).balanceOf(escrow), 0);
    assertEq(IERC20(fromToken).balanceOf(collector), collectorSellBefore - cfg.twapPartAmount);
  }

  function test_twapSwap_twoSameFromToken() public {
    address fromToken = cfg.fromToken;
    uint256 total = cfg.twapPartAmount * TWAP_NUM_PARTS;
    TWAPOrder.Data memory data = _twapData(block.timestamp, 0);

    address first = _twapSwap(guardian, data);
    address second = _twapSwap(guardian, data);

    assertNotEq(first, second);
    assertEq(IERC20(fromToken).balanceOf(first), total);
    assertEq(IERC20(fromToken).balanceOf(second), total);
    assertEq(IERC20(fromToken).allowance(first, VAULT_RELAYER), total);
    assertEq(IERC20(fromToken).allowance(second, VAULT_RELAYER), total);

    (, bytes32 firstHash) = steward.swaps(first);
    (, bytes32 secondHash) = steward.swaps(second);
    assertEq(firstHash, secondHash);
    assertTrue(IComposableCow(COMPOSABLE_COW).singleOrders(first, firstHash));
    assertTrue(IComposableCow(COMPOSABLE_COW).singleOrders(second, secondHash));

    vm.prank(guardian);
    steward.cancelSwap(first);

    assertFalse(IComposableCow(COMPOSABLE_COW).singleOrders(first, firstHash));
    assertTrue(IComposableCow(COMPOSABLE_COW).singleOrders(second, secondHash));
    assertEq(IERC20(fromToken).balanceOf(second), total);
    assertEq(IERC20(fromToken).allowance(second, VAULT_RELAYER), total);
  }

  function test_swapEscrow_revertsWith_OnlySteward_close() public {
    address escrow = _swap(guardian, cfg.fromToken, cfg.toToken, cfg.swapAmount);
    (, bytes32 orderHash) = steward.swaps(escrow);

    vm.prank(alice);
    vm.expectRevert(SwapEscrow.OnlySteward.selector);
    SwapEscrow(escrow).close(orderHash, IERC20(cfg.fromToken), alice);
  }

  function test_swapEscrow_revertsWith_OnlySteward_open() public {
    address escrow = _swap(guardian, cfg.fromToken, cfg.toToken, cfg.swapAmount);

    vm.prank(alice);
    vm.expectRevert(SwapEscrow.OnlySteward.selector);
    SwapEscrow(escrow)
      .open(
        IConditionalOrder.ConditionalOrderParams(IConditionalOrder(address(0)), bytes32(0), ""),
        IERC20(cfg.fromToken),
        1
      );
  }

  function test_getExpectedOut_revertsWith_OracleNotSet_fromOracleUnset() public {
    vm.expectRevert(ISwapSteward.OracleNotSet.selector);
    steward.getExpectedOut(1e18, cfg.otherToken, cfg.toToken);
  }

  function test_getExpectedOut_revertsWith_OracleNotSet_toOracleUnset() public {
    vm.expectRevert(ISwapSteward.OracleNotSet.selector);
    steward.getExpectedOut(1e18, cfg.toToken, cfg.otherToken);
  }

  function test_getExpectedOut() public {
    address fromToken = cfg.fromToken;
    address toToken = cfg.toToken;
    uint256 amount = 10 * cfg.swapAmount;

    uint256 result = steward.getExpectedOut(amount, fromToken, toToken);

    assertEq(result, _expectedOut(amount));
  }

  function test_settle() public {
    address fromToken = cfg.fromToken;
    address toToken = cfg.toToken;
    address collector = cfg.collector;
    address escrow = _swap(guardian, fromToken, toToken, cfg.swapAmount);
    uint32 validUntil = uint32(block.timestamp + 1 days);

    (GPv2Order.Data memory order, bytes memory signature) =
      _getMarketOrderWithSignature(escrow, fromToken, toToken, validUntil);

    uint256 expectedBuyAmount = _expectedOut(cfg.swapAmount) * (BPS - SWAP_SLIPPAGE) / BPS;
    assertGt(expectedBuyAmount, 0);
    assertEq(order.buyAmount, expectedBuyAmount);

    uint256 collectorBuyBefore = IERC20(toToken).balanceOf(collector);
    deal(toToken, GPV2_SETTLEMENT, order.buyAmount);
    _settle(escrow, order, signature);

    assertEq(IERC20(toToken).balanceOf(collector), collectorBuyBefore + expectedBuyAmount);
    assertEq(IERC20(fromToken).balanceOf(escrow), 0);
    assertEq(IGPv2SettlementTest(GPV2_SETTLEMENT).filledAmount(_orderUid(escrow, order)), cfg.swapAmount);
  }

  function test_settle_stableWithinOracleRound() public {
    address fromToken = cfg.fromToken;
    address toToken = cfg.toToken;
    address escrow = _swap(guardian, fromToken, toToken, cfg.swapAmount);
    uint32 validUntil = uint32(block.timestamp + 1 days);

    (GPv2Order.Data memory first, bytes memory firstSignature) =
      _getMarketOrderWithSignature(escrow, fromToken, toToken, validUntil);

    vm.warp(block.timestamp + 1 hours);

    (GPv2Order.Data memory second,) = _getMarketOrderWithSignature(escrow, fromToken, toToken, validUntil);

    bytes32 domainSeparator = IGPv2Settlement(GPV2_SETTLEMENT).domainSeparator();
    assertEq(GPv2Order.hash(first, domainSeparator), GPv2Order.hash(second, domainSeparator));
    assertEq(first.validTo, second.validTo);
    assertEq(_orderUid(escrow, first), _orderUid(escrow, second));
    deal(address(first.buyToken), GPV2_SETTLEMENT, first.buyAmount);

    _settle(escrow, first, firstSignature);
    assertEq(IGPv2SettlementTest(GPV2_SETTLEMENT).filledAmount(_orderUid(escrow, first)), cfg.swapAmount);
  }

  function test_settle_revertsWith_InvalidHash() public {
    address fromToken = cfg.fromToken;
    address toToken = cfg.toToken;
    address escrow = _swap(guardian, fromToken, toToken, cfg.swapAmount);

    (GPv2Order.Data memory order, bytes memory signature) =
      _getMarketOrderWithSignature(escrow, fromToken, toToken, uint32(block.timestamp + 1 days));

    order.buyAmount -= 1;
    deal(address(order.buyToken), GPV2_SETTLEMENT, order.buyAmount);
    vm.expectRevert(ERC1271Forwarder.InvalidHash.selector);
    _settle(escrow, order, signature);
  }

  function test_settle_revertsWith_OrderNotValid() public {
    address fromToken = cfg.fromToken;
    address toToken = cfg.toToken;
    address escrow = _swap(guardian, fromToken, toToken, cfg.swapAmount);
    uint32 validUntil = uint32(block.timestamp + 1 days);

    (GPv2Order.Data memory order, bytes memory signature) =
      _getMarketOrderWithSignature(escrow, fromToken, toToken, validUntil);

    int256 currentAnswer = IAggregatorInterface(cfg.toOracle).latestAnswer();
    vm.mockCall(
      cfg.toOracle,
      abi.encodeWithSelector(IAggregatorInterface.latestAnswer.selector),
      abi.encode(currentAnswer * int256(BPS + ORACLE_MOVE_BPS) / int256(BPS))
    );

    (GPv2Order.Data memory refreshed,) = _getMarketOrderWithSignature(escrow, fromToken, toToken, validUntil);
    assertNotEq(refreshed.buyAmount, order.buyAmount);
    deal(address(refreshed.buyToken), GPV2_SETTLEMENT, refreshed.buyAmount);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, INVALID_HASH));
    _settle(escrow, order, signature);
  }

  function _expectedOut(uint256 amount) internal view returns (uint256) {
    uint256 pFrom = uint256(IAggregatorInterface(cfg.fromOracle).latestAnswer());
    uint256 pTo = uint256(IAggregatorInterface(cfg.toOracle).latestAnswer());
    return (amount * pFrom * 10 ** IERC20Metadata(cfg.toToken).decimals())
      / (pTo * 10 ** IERC20Metadata(cfg.fromToken).decimals());
  }

  function _marketData(address fromToken, address toToken, uint256 amount, uint32 validUntil)
    internal
    view
    returns (OracleMarketOrder.Data memory)
  {
    return OracleMarketOrder.Data({
      fromToken: fromToken,
      toToken: toToken,
      fromOracle: steward.priceOracle(fromToken),
      toOracle: steward.priceOracle(toToken),
      receiver: cfg.collector,
      sellAmount: amount,
      slippage: SWAP_SLIPPAGE,
      appData: APP_DATA,
      validUntil: validUntil,
      sequencerUptimeFeed: cfg.sequencerUptimeFeed,
      sequencerGracePeriod: steward.SEQUENCER_GRACE_PERIOD()
    });
  }

  function _marketParams(OracleMarketOrder.Data memory data)
    internal
    view
    returns (IConditionalOrder.ConditionalOrderParams memory)
  {
    return IConditionalOrder.ConditionalOrderParams(
      IConditionalOrder(address(marketOrderHandler)), bytes32(0), abi.encode(data)
    );
  }

  function _getMarketOrderWithSignature(address owner, address fromToken, address toToken, uint32 validUntil)
    internal
    view
    returns (GPv2Order.Data memory, bytes memory)
  {
    return IComposableCow(COMPOSABLE_COW)
      .getTradeableOrderWithSignature(
        owner, _marketParams(_marketData(fromToken, toToken, cfg.swapAmount, validUntil)), "", new bytes32[](0)
      );
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

  function _twapData(uint256 startTime, uint256 span) internal view returns (TWAPOrder.Data memory) {
    return TWAPOrder.Data({
      sellToken: IERC20(cfg.fromToken),
      buyToken: IERC20(cfg.toToken),
      receiver: cfg.collector,
      partSellAmount: cfg.twapPartAmount,
      minPartLimit: cfg.twapMinPartLimit,
      t0: startTime,
      n: TWAP_NUM_PARTS,
      t: TWAP_PART_DURATION,
      span: span,
      appData: APP_DATA
    });
  }

  function _twapParams(TWAPOrder.Data memory data)
    internal
    pure
    returns (IConditionalOrder.ConditionalOrderParams memory)
  {
    return IConditionalOrder.ConditionalOrderParams(IConditionalOrder(TWAP_HANDLER), bytes32(0), abi.encode(data));
  }

  /// @dev Orders of a TWAP are generated from its resolved start time `t0`
  function _getTwapOrderWithSignature(address owner, uint256 t0, uint256 span)
    internal
    view
    returns (GPv2Order.Data memory, bytes memory)
  {
    return IComposableCow(COMPOSABLE_COW)
      .getTradeableOrderWithSignature(owner, _twapParams(_twapData(t0, span)), "", new bytes32[](0));
  }

  function _twapSwap(address caller, TWAPOrder.Data memory data) internal returns (address) {
    address escrow = vm.computeCreateAddress(address(steward), vm.getNonce(address(steward)));
    vm.prank(caller);
    steward.twapSwap(
      address(data.sellToken),
      address(data.buyToken),
      data.partSellAmount,
      data.minPartLimit,
      data.t0,
      data.n,
      data.t,
      data.span
    );
    return escrow;
  }

  function _approvePairsWithOtherToken() internal {
    vm.startPrank(cfg.executor);
    steward.setSwappablePair(cfg.fromToken, cfg.otherToken, true);
    steward.setSwappablePair(cfg.otherToken, cfg.fromToken, true);
    vm.stopPrank();
  }

  function _swap(address caller, address fromToken, address toToken, uint256 amount) internal returns (address) {
    address escrow = vm.computeCreateAddress(address(steward), vm.getNonce(address(steward)));
    vm.prank(caller);
    steward.swap(fromToken, toToken, amount, SWAP_SLIPPAGE);
    return escrow;
  }

  function createSteward(
    address collector,
    address composableCow,
    address marketOrderHandler_,
    address twapHandler,
    address vaultRelayer
  ) external returns (SwapSteward) {
    return new SwapSteward(
      cfg.executor,
      guardian,
      collector,
      composableCow,
      marketOrderHandler_,
      twapHandler,
      vaultRelayer,
      cfg.sequencerUptimeFeed
    );
  }
}
