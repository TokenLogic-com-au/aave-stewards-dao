// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";
import {RescuableBase} from "solidity-utils/contracts/utils/RescuableBase.sol";

import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";

import {IAggregatorInterface} from "src/finance/interfaces/IAggregatorInterface.sol";
import {IComposableCow} from "src/finance/interfaces/IComposableCow.sol";
import {IConditionalOrder} from "src/finance/interfaces/IConditionalOrder.sol";
import {OracleMarketOrder} from "src/finance/OracleMarketOrder.sol";
import {OracleMath} from "src/finance/libraries/OracleMath.sol";
import {TWAPOrder} from "src/finance/libraries/TWAPOrder.sol";
import {SwapEscrow} from "src/finance/SwapEscrow.sol";
import {ISwapSteward} from "src/finance/interfaces/ISwapSteward.sol";

/**
 * @title SwapSteward
 * @author halaprix (Tokenlogic)
 * @notice Facilitates token swaps on behalf of the DAO Treasury through Composable CoW.
 * Same role, budget, pair and oracle model as MainnetSwapSteward, without Milkman.
 * The receiver of every swap is the Collector. Each swap is owned by its own SwapEscrow clone,
 * which holds only that swap's sell tokens and relayer allowance.
 */
contract SwapSteward is ISwapSteward, OwnableWithGuardian, Multicall, RescuableBase {
  using SafeERC20 for IERC20;

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
    address fromOracle = priceOracle[fromToken];
    address toOracle = priceOracle[toToken];
    amount = _checkAmount(fromToken, amount);

    _validateSwap(fromToken, toToken, fromOracle, toOracle, amount, slippage);

    IConditionalOrder.ConditionalOrderParams memory params = IConditionalOrder.ConditionalOrderParams(
      IConditionalOrder(MARKET_ORDER_HANDLER),
      bytes32(0),
      abi.encode(
        OracleMarketOrder.Data({
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
        })
      )
    );

    (address escrow, bytes32 orderHash) = _openSwap(fromToken, amount, params);

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

    _validateCommon(fromToken, toToken, amount);
    if (startTime != 0 && startTime < block.timestamp) revert StartTimeInPast();

    TWAPOrder.Data memory twap = TWAPOrder.Data({
      sellToken: IERC20(fromToken),
      buyToken: IERC20(toToken),
      receiver: COLLECTOR,
      partSellAmount: partSellAmount,
      minPartLimit: minPartLimit,
      t0: startTime == 0 ? block.timestamp : startTime,
      n: numParts,
      t: partDuration,
      span: span,
      appData: APP_DATA
    });
    TWAPOrder.validate(twap);

    (address escrow, bytes32 orderHash) = _openSwap(
      fromToken,
      amount,
      IConditionalOrder.ConditionalOrderParams(IConditionalOrder(TWAP_HANDLER), bytes32(0), abi.encode(twap))
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

    // Validate oracle has necessary functions
    if (IAggregatorInterface(oracle).decimals() != 8) {
      revert PriceFeedIncompatibleDecimals();
    }
    if (IAggregatorInterface(oracle).latestAnswer() <= 0) {
      revert PriceFeedInvalidAnswer();
    }

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

  /// @inheritdoc ISwapSteward
  function getExpectedOut(uint256 amount, address fromToken, address toToken) external view returns (uint256) {
    address fromOracle = priceOracle[fromToken];
    address toOracle = priceOracle[toToken];
    if (fromOracle == address(0) || toOracle == address(0)) revert OracleNotSet();

    return OracleMath.getExpectedOut(fromToken, toToken, fromOracle, toOracle, amount);
  }

  /// @inheritdoc RescuableBase
  function maxRescue(address token) public view override(RescuableBase) returns (uint256) {
    return IERC20(token).balanceOf(address(this));
  }

  /// @dev Internal function to check maximum amount
  function _checkAmount(address fromToken, uint256 amount) internal view returns (uint256) {
    if (amount == type(uint256).max) {
      amount = msg.sender == owner() ? IERC20(fromToken).balanceOf(COLLECTOR) : tokenBudget[fromToken];
    }

    return amount;
  }

  function _transferTokensTo(address fromToken, address to, uint256 amount) internal {
    ICollector(COLLECTOR).transfer(IERC20(fromToken), to, amount);
  }

  /// @dev Internal function to deploy the SwapEscrow clone of a swap, fund it from the Collector and open its order.
  /// Guardian swaps consume the token budget
  function _openSwap(address fromToken, uint256 amount, IConditionalOrder.ConditionalOrderParams memory params)
    internal
    returns (address escrow, bytes32 orderHash)
  {
    escrow = Clones.clone(SWAP_ESCROW_IMPLEMENTATION);
    _transferTokensTo(fromToken, escrow, amount);
    if (msg.sender != owner()) {
      _decreaseBudget(fromToken, amount);
    }

    orderHash = COMPOSABLE_COW.hash(params);
    swaps[escrow] = Swap({fromToken: fromToken, orderHash: orderHash});

    SwapEscrow(escrow).open(params, IERC20(fromToken), amount);
  }

  /// @dev Internal function to validate a swap's parameters
  function _validateSwap(
    address fromToken,
    address toToken,
    address fromOracle,
    address toOracle,
    uint256 amount,
    uint256 slippage
  ) internal view {
    if (slippage > MAX_SLIPPAGE) revert InvalidSlippage();

    _validateCommon(fromToken, toToken, amount);

    if (fromOracle == address(0) || toOracle == address(0)) revert OracleNotSet();
    if (IAggregatorInterface(fromOracle).latestAnswer() <= 0 || IAggregatorInterface(toOracle).latestAnswer() <= 0) {
      revert PriceFeedInvalidAnswer();
    }
  }

  /// @dev Internal function to perform common validation of swaps
  function _validateCommon(address fromToken, address toToken, uint256 amount) internal view {
    if (amount == 0) revert InvalidZeroAmount();
    if (!swapApprovedPair[fromToken][toToken]) {
      revert UnrecognizedTokenSwap();
    }
  }

  /// @dev Internal function to decrease token budget
  function _decreaseBudget(address fromToken, uint256 amount) internal {
    if (amount > tokenBudget[fromToken]) revert InsufficientBudget();
    tokenBudget[fromToken] -= amount;

    emit UpdatedTokenBudget(fromToken, tokenBudget[fromToken]);
  }

  /// @dev Internal function to increase token budget
  function _increaseBudget(address fromToken, uint256 amount) internal {
    tokenBudget[fromToken] += amount;

    emit UpdatedTokenBudget(fromToken, tokenBudget[fromToken]);
  }
}
