// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";
import {RescuableBase} from "solidity-utils/contracts/utils/RescuableBase.sol";

import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";
import {AggregatorInterface} from "aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol";

import {IConditionalOrder} from "composable-cow/interfaces/IConditionalOrder.sol";
import {TWAPOrder} from "composable-cow/types/twap/libraries/TWAPOrder.sol";
import {IERC20 as GPv2IERC20} from "cowprotocol/contracts/interfaces/IERC20.sol";

import {IComposableCow} from "src/finance/interfaces/IComposableCow.sol";
import {OracleMarketOrder} from "src/finance/swap/OracleMarketOrder.sol";
import {OracleMath} from "src/finance/swap/libraries/OracleMath.sol";
import {SwapEscrow} from "src/finance/swap/SwapEscrow.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";

/**
 * @title SwapSteward
 * @author halaprix (Tokenlogic)
 * @notice Facilitates token swaps on behalf of the DAO Treasury through Composable CoW.
 * Same role, budget, pair and oracle model as MainnetSwapSteward, without Milkman.
 * The receiver of every swap is the Collector. Each swap is owned by its own SwapEscrow clone,
 * which holds only that swap's sell tokens and relayer allowance.
 */
contract SwapSteward is ISwapSteward, OwnableWithGuardian, Multicall, RescuableBase {
  /// @inheritdoc ISwapSteward
  uint256 public constant MAX_SLIPPAGE = 10_00; // 10%

  /// @inheritdoc ISwapSteward
  uint32 public constant ORDER_LIFETIME = 1 days;

  /// @inheritdoc ISwapSteward
  uint32 public constant SEQUENCER_GRACE_PERIOD = 1 hours;

  /// @inheritdoc ISwapSteward
  bytes32 public constant APP_DATA = bytes32(0);

  /// @inheritdoc ISwapSteward
  address public immutable COLLECTOR;

  /// @inheritdoc ISwapSteward
  IComposableCow public immutable COMPOSABLE_COW;

  /// @inheritdoc ISwapSteward
  address public immutable SWAP_ESCROW_IMPLEMENTATION;

  /// @inheritdoc ISwapSteward
  address public immutable MARKET_ORDER_HANDLER;

  /// @inheritdoc ISwapSteward
  address public immutable TWAP_HANDLER;

  /// @inheritdoc ISwapSteward
  address public immutable SEQUENCER_UPTIME_FEED;

  /// @inheritdoc ISwapSteward
  mapping(address fromToken => mapping(address toToken => bool isApproved)) public swapApprovedPair;

  /// @inheritdoc ISwapSteward
  mapping(address token => address oracle) public priceOracle;

  /// @inheritdoc ISwapSteward
  mapping(address token => uint256 budget) public tokenBudget;

  /// @inheritdoc ISwapSteward
  mapping(address escrow => Swap swap) public swaps;

  constructor(
    address initialOwner,
    address initialGuardian,
    address collector,
    address composableCow,
    address marketOrderHandler,
    address twapHandler,
    address vaultRelayer,
    address sequencerUptimeFeed
  ) OwnableWithGuardian(initialOwner, initialGuardian) {
    if (
      collector == address(0) || composableCow == address(0) || marketOrderHandler == address(0)
        || twapHandler == address(0) || vaultRelayer == address(0)
    ) revert InvalidZeroAddress();

    COLLECTOR = collector;
    COMPOSABLE_COW = IComposableCow(composableCow);
    SWAP_ESCROW_IMPLEMENTATION = address(new SwapEscrow(composableCow, vaultRelayer));
    MARKET_ORDER_HANDLER = marketOrderHandler;
    TWAP_HANDLER = twapHandler;
    SEQUENCER_UPTIME_FEED = sequencerUptimeFeed;
  }

  /// @inheritdoc ISwapSteward
  function swap(address fromToken, address toToken, uint256 amount, uint256 slippage) external onlyOwnerOrGuardian {
    amount = _resolveAmount(fromToken, amount);
    (address fromOracle, address toOracle) = _validateSwap(fromToken, toToken, amount, slippage);

    (address escrow, bytes32 orderHash) =
      _openSwap(fromToken, amount, _marketOrder(fromToken, toToken, fromOracle, toOracle, amount, slippage));

    emit SwapRequested(escrow, orderHash, fromToken, toToken, fromOracle, toOracle, amount, slippage);
  }

  /// @inheritdoc ISwapSteward
  function twapSwap(
    address fromToken,
    address toToken,
    uint256 partSellAmount,
    uint256 minPartLimit,
    uint256 startTime,
    uint256 numParts,
    uint256 partDuration,
    uint256 span
  ) external onlyOwnerOrGuardian {
    uint256 amount = partSellAmount * numParts;
    _validateTwap(fromToken, toToken, amount, startTime);

    (address escrow, bytes32 orderHash) = _openSwap(
      fromToken,
      amount,
      _twapOrder(fromToken, toToken, partSellAmount, minPartLimit, startTime, numParts, partDuration, span)
    );

    emit TWAPSwapRequested(escrow, orderHash, fromToken, toToken, amount);
  }

  /// @inheritdoc ISwapSteward
  function cancelSwap(address escrow) external onlyOwnerOrGuardian {
    Swap memory pending = swaps[escrow];
    if (pending.orderHash == bytes32(0)) revert SwapNotFound();
    delete swaps[escrow];

    uint256 amount = SwapEscrow(escrow).close(pending.orderHash, IERC20(pending.fromToken), COLLECTOR);

    emit SwapCanceled(escrow, pending.orderHash, pending.fromToken, amount);
  }

  /// @inheritdoc ISwapSteward
  function increaseTokenBudget(address token, uint256 budget) external onlyOwner {
    _increaseBudget(token, budget);
  }

  /// @inheritdoc ISwapSteward
  function decreaseTokenBudget(address token, uint256 budget) external onlyOwner {
    _decreaseBudget(token, budget);
  }

  /// @inheritdoc ISwapSteward
  function setSwappablePair(address fromToken, address toToken, bool allowed) external onlyOwner {
    if (fromToken == toToken) revert UnrecognizedTokenSwap();

    swapApprovedPair[fromToken][toToken] = allowed;

    emit SetSwappablePair(fromToken, toToken, allowed);
  }

  /// @inheritdoc ISwapSteward
  function setTokenOracle(address token, address oracle) external onlyOwner {
    if (oracle == address(0)) revert InvalidZeroAddress();
    if (AggregatorInterface(oracle).decimals() != 8) revert PriceFeedIncompatibleDecimals();
    _requirePositivePrice(oracle);

    priceOracle[token] = oracle;

    emit SetTokenOracle(token, oracle);
  }

  /// @inheritdoc ISwapSteward
  function rescueToken(address token) external onlyOwnerOrGuardian {
    _emergencyTokenTransfer(token, COLLECTOR, type(uint256).max);
  }

  /// @inheritdoc ISwapSteward
  function rescueToken(address token, uint256 amount) external onlyOwnerOrGuardian {
    _emergencyTokenTransfer(token, COLLECTOR, amount);
  }

  /// @inheritdoc RescuableBase
  function maxRescue(address token) public view override(RescuableBase) returns (uint256) {
    return IERC20(token).balanceOf(address(this));
  }

  /// @inheritdoc ISwapSteward
  function getExpectedOut(uint256 amount, address fromToken, address toToken) external view returns (uint256) {
    (address fromOracle, address toOracle) = _getOracles(fromToken, toToken);

    return OracleMath.getExpectedOut(fromToken, toToken, fromOracle, toOracle, amount);
  }

  /// @dev Deploys the SwapEscrow clone of a swap, funds it from the Collector and opens its order.
  /// Guardian swaps consume the token budget; owner swaps do not.
  function _openSwap(address fromToken, uint256 amount, IConditionalOrder.ConditionalOrderParams memory params)
    internal
    returns (address escrow, bytes32 orderHash)
  {
    escrow = Clones.clone(SWAP_ESCROW_IMPLEMENTATION);
    ICollector(COLLECTOR).transfer(IERC20(fromToken), escrow, amount);
    if (msg.sender != owner()) _decreaseBudget(fromToken, amount);

    orderHash = COMPOSABLE_COW.hash(params);
    swaps[escrow] = Swap({fromToken: fromToken, orderHash: orderHash});

    SwapEscrow(escrow).open(params, IERC20(fromToken), amount);
  }

  /// @dev Builds the conditional order params of an oracle-priced market order paying out to the Collector.
  function _marketOrder(
    address fromToken,
    address toToken,
    address fromOracle,
    address toOracle,
    uint256 amount,
    uint256 slippage
  ) internal view returns (IConditionalOrder.ConditionalOrderParams memory) {
    OracleMarketOrder.Data memory order = OracleMarketOrder.Data({
      fromToken: fromToken,
      toToken: toToken,
      fromOracle: fromOracle,
      toOracle: toOracle,
      receiver: COLLECTOR,
      sellAmount: amount,
      slippage: slippage,
      appData: APP_DATA,
      validUntil: SafeCast.toUint32(block.timestamp + ORDER_LIFETIME),
      sequencerUptimeFeed: SEQUENCER_UPTIME_FEED,
      sequencerGracePeriod: SEQUENCER_GRACE_PERIOD
    });

    return
      IConditionalOrder.ConditionalOrderParams(IConditionalOrder(MARKET_ORDER_HANDLER), bytes32(0), abi.encode(order));
  }

  /// @dev Builds and validates the conditional order params of a TWAP order paying out to the Collector.
  /// A zero `startTime` starts the TWAP at the current block.
  function _twapOrder(
    address fromToken,
    address toToken,
    uint256 partSellAmount,
    uint256 minPartLimit,
    uint256 startTime,
    uint256 numParts,
    uint256 partDuration,
    uint256 span
  ) internal view returns (IConditionalOrder.ConditionalOrderParams memory) {
    TWAPOrder.Data memory order = TWAPOrder.Data({
      sellToken: GPv2IERC20(fromToken),
      buyToken: GPv2IERC20(toToken),
      receiver: COLLECTOR,
      partSellAmount: partSellAmount,
      minPartLimit: minPartLimit,
      t0: startTime == 0 ? block.timestamp : startTime,
      n: numParts,
      t: partDuration,
      span: span,
      appData: APP_DATA
    });
    TWAPOrder.validate(order);

    return IConditionalOrder.ConditionalOrderParams(IConditionalOrder(TWAP_HANDLER), bytes32(0), abi.encode(order));
  }

  /// @dev Validates a market swap and returns the oracles that price it.
  function _validateSwap(address fromToken, address toToken, uint256 amount, uint256 slippage)
    internal
    view
    returns (address fromOracle, address toOracle)
  {
    if (slippage > MAX_SLIPPAGE) revert InvalidSlippage();
    _validateCommon(fromToken, toToken, amount);

    (fromOracle, toOracle) = _getOracles(fromToken, toToken);
    _requirePositivePrice(fromOracle);
    _requirePositivePrice(toOracle);
  }

  /// @dev Validates a TWAP swap. Part/timing checks are left to `TWAPOrder.validate`.
  function _validateTwap(address fromToken, address toToken, uint256 amount, uint256 startTime) internal view {
    _validateCommon(fromToken, toToken, amount);
    if (startTime != 0 && startTime < block.timestamp) revert StartTimeInPast();
  }

  /// @dev Checks shared by every swap type: non-zero amount and an approved pair.
  function _validateCommon(address fromToken, address toToken, uint256 amount) internal view {
    if (amount == 0) revert InvalidZeroAmount();
    if (!swapApprovedPair[fromToken][toToken]) revert UnrecognizedTokenSwap();
  }

  /// @dev Returns the oracles of both tokens, reverting if either is not set.
  function _getOracles(address fromToken, address toToken)
    internal
    view
    returns (address fromOracle, address toOracle)
  {
    fromOracle = priceOracle[fromToken];
    toOracle = priceOracle[toToken];
    if (fromOracle == address(0) || toOracle == address(0)) revert OracleNotSet();
  }

  /// @dev Reverts unless the oracle reports a strictly positive price.
  function _requirePositivePrice(address oracle) internal view {
    if (AggregatorInterface(oracle).latestAnswer() <= 0) revert PriceFeedInvalidAnswer();
  }

  /// @dev Resolves the `type(uint256).max` sentinel: the owner sells the Collector's full balance,
  /// the guardian sells its full remaining budget. Any other amount is returned as is.
  function _resolveAmount(address fromToken, uint256 amount) internal view returns (uint256) {
    if (amount != type(uint256).max) return amount;
    return msg.sender == owner() ? IERC20(fromToken).balanceOf(COLLECTOR) : tokenBudget[fromToken];
  }

  /// @dev Increases the guardian's budget for a token.
  function _increaseBudget(address token, uint256 amount) internal {
    tokenBudget[token] += amount;

    emit UpdatedTokenBudget(token, tokenBudget[token]);
  }

  /// @dev Decreases the guardian's budget for a token, reverting if it would go negative.
  function _decreaseBudget(address token, uint256 amount) internal {
    if (amount > tokenBudget[token]) revert InsufficientBudget();
    tokenBudget[token] -= amount;

    emit UpdatedTokenBudget(token, tokenBudget[token]);
  }
}
