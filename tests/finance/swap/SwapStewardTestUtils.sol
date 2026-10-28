// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {GPv2Order} from "src/finance/libraries/GPv2Order.sol";
import {IConditionalOrder} from "src/finance/interfaces/IConditionalOrder.sol";
import {TWAPOrder} from "src/finance/libraries/TWAPOrder.sol";
import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";
import {OracleMarketOrder} from "src/finance/swap/OracleMarketOrder.sol";
import {SwapSteward} from "src/finance/swap/SwapSteward.sol";
import {IComposableCow} from "src/finance/interfaces/IComposableCow.sol";
import {IGPv2AllowListAuthentication} from "src/finance/interfaces/IGPv2AllowListAuthentication.sol";
import {IGPv2Settlement} from "src/finance/interfaces/IGPv2Settlement.sol";

/**
 * @dev Constants, state and helpers shared by the SwapSteward unit fixture on a pinned mainnet fork and the SwapSteward fork fixture.
 * A fixture assigns the environment fields in its `setUp`, then calls `_deploySteward` and `_allowSolver`.
 */
abstract contract SwapStewardTestUtils is Test {
  address internal constant GPV2_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
  uint256 internal constant SWAP_SLIPPAGE = 50;
  uint256 internal constant TWAP_NUM_PARTS = 4;
  uint256 internal constant TWAP_PART_DURATION = 1 hours;
  string internal constant GPV2_ORDER_FILLED = "GPv2: order filled";
  /// @dev GPv2Trade flags: bits 0-4 = 0 (sell, fill-or-kill, ERC20 sell and buy balances); bits 5-6 = signing
  /// scheme.
  /// https://github.com/cowprotocol/contracts/blob/a10f40788af29467e87de3dbf2196662b0a6b500/src/contracts/libraries/GPv2Trade.sol#L58-L131
  /// https://github.com/cowprotocol/contracts/blob/a10f40788af29467e87de3dbf2196662b0a6b500/src/contracts/mixins/GPv2Signing.sol#L24-L29
  uint256 internal constant FLAGS_SIGNING_SCHEME_OFFSET = 5;
  uint256 internal constant SIGNING_SCHEME_EIP1271 = 2;
  uint256 internal constant FLAGS_SELL_FILL_OR_KILL_EIP1271 = SIGNING_SCHEME_EIP1271 << FLAGS_SIGNING_SCHEME_OFFSET;
  uint256 internal constant MAINNET_FORK_BLOCK = 26148310; // https://etherscan.io/block/26148310
  /// @dev Revert reason of the TWAP handler before the order start, from composable-cow `TWAPOrderMathLib`
  string internal constant BEFORE_TWAP_START = "before twap start";

  address internal guardian = makeAddr("guardian");
  address internal solver = makeAddr("solver");

  address internal executor;
  address internal collector;
  address internal sequencerUptimeFeed;
  address internal fromToken;
  address internal fromOracle;
  address internal toToken;
  address internal toOracle;
  uint256 internal swapAmount;
  uint256 internal guardianBudget;
  uint256 internal twapPartAmount;
  uint256 internal twapMinPartLimit;

  IComposableCow internal composableCow;
  address internal twapHandler;
  address internal vaultRelayer;
  IGPv2Settlement internal settlement;
  OracleMarketOrder internal marketOrderHandler;
  SwapSteward internal steward;
  bytes32 internal appData;
  uint256 internal sequencerGracePeriod;

  function _deploySteward() internal {
    marketOrderHandler = new OracleMarketOrder();
    steward = new SwapSteward(
      executor,
      guardian,
      collector,
      address(composableCow),
      address(marketOrderHandler),
      twapHandler,
      vaultRelayer,
      sequencerUptimeFeed
    );
    appData = steward.APP_DATA();
    sequencerGracePeriod = steward.SEQUENCER_GRACE_PERIOD();

    bytes32 fundsAdminRole = ICollector(collector).FUNDS_ADMIN_ROLE();
    vm.startPrank(executor);
    IAccessControl(collector).grantRole(fundsAdminRole, address(steward));
    steward.setSwappablePair(fromToken, toToken);
    steward.setTokenOracle(fromToken, fromOracle);
    steward.setTokenOracle(toToken, toOracle);
    steward.increaseGuardianTokenBudget(fromToken, guardianBudget);
    vm.stopPrank();
  }

  function _allowSolver() internal {
    IGPv2AllowListAuthentication authenticator = settlement.authenticator();
    vm.prank(authenticator.manager());
    authenticator.addSolver(solver);
  }

  function _expectedEscrow() internal view returns (address) {
    return vm.computeCreateAddress(address(steward), vm.getNonce(address(steward)));
  }

  function _marketData(uint256 amount, uint32 validTo) internal view returns (OracleMarketOrder.Data memory) {
    return OracleMarketOrder.Data({
      fromToken: fromToken,
      toToken: toToken,
      fromOracle: fromOracle,
      toOracle: toOracle,
      receiver: collector,
      sellAmount: amount,
      slippage: SWAP_SLIPPAGE,
      appData: appData,
      validTo: validTo,
      sequencerUptimeFeed: sequencerUptimeFeed,
      sequencerGracePeriod: sequencerGracePeriod
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

  function _getMarketOrderWithSignature(address owner, uint32 validTo)
    internal
    view
    returns (GPv2Order.Data memory, bytes memory)
  {
    return composableCow.getTradeableOrderWithSignature(
      owner, _marketParams(_marketData(swapAmount, validTo)), "", new bytes32[](0)
    );
  }

  /// @dev GPv2Settlement exposes no UID getter; `filledAmount` is keyed by the packed UID (digest, owner, validTo).
  /// https://github.com/cowprotocol/contracts/blob/a10f40788af29467e87de3dbf2196662b0a6b500/src/contracts/libraries/GPv2Order.sol#L167-L212
  function _orderUid(address owner, GPv2Order.Data memory order) internal view returns (bytes memory orderUid) {
    orderUid = abi.encodePacked(GPv2Order.hash(order, settlement.domainSeparator()), owner, order.validTo);
  }

  function _settle(address owner, GPv2Order.Data memory order, bytes memory signature) internal {
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = order.sellToken;
    tokens[1] = order.buyToken;

    uint256[] memory clearingPrices = new uint256[](2);
    clearingPrices[0] = order.buyAmount;
    clearingPrices[1] = order.sellAmount;

    IGPv2Settlement.Trade[] memory trades = new IGPv2Settlement.Trade[](1);
    trades[0] = IGPv2Settlement.Trade({
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
    IGPv2Settlement.Interaction[][3] memory interactions;

    vm.prank(solver);
    settlement.settle(tokens, clearingPrices, trades, interactions);
  }

  function _twapData(uint256 startTime, uint256 span) internal view returns (TWAPOrder.Data memory) {
    return TWAPOrder.Data({
      sellToken: IERC20(fromToken),
      buyToken: IERC20(toToken),
      receiver: collector,
      partSellAmount: twapPartAmount,
      minPartLimit: twapMinPartLimit,
      t0: startTime,
      n: TWAP_NUM_PARTS,
      t: TWAP_PART_DURATION,
      span: span,
      appData: appData
    });
  }

  function _twapParams(TWAPOrder.Data memory data)
    internal
    view
    returns (IConditionalOrder.ConditionalOrderParams memory)
  {
    return IConditionalOrder.ConditionalOrderParams(IConditionalOrder(twapHandler), bytes32(0), abi.encode(data));
  }

  /// @dev Orders of a TWAP are generated from its resolved start time `t0`
  function _getTwapOrderWithSignature(address owner, uint256 t0)
    internal
    view
    returns (GPv2Order.Data memory, bytes memory)
  {
    return composableCow.getTradeableOrderWithSignature(owner, _twapParams(_twapData(t0, 0)), "", new bytes32[](0));
  }

  function _twapSwap(address caller, TWAPOrder.Data memory data) internal returns (address) {
    address escrow = _expectedEscrow();
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

  function _swap(address caller, address sellToken, address buyToken, uint256 amount) internal returns (address) {
    address escrow = _expectedEscrow();
    vm.prank(caller);
    steward.swap(sellToken, buyToken, amount, SWAP_SLIPPAGE);
    return escrow;
  }
}
