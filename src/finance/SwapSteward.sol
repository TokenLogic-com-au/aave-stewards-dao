// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";
import {RescuableBase} from "solidity-utils/contracts/utils/RescuableBase.sol";

import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";

import {ERC1271Forwarder} from "src/finance/ERC1271Forwarder.sol";
import {IAggregatorInterface} from "src/finance/interfaces/IAggregatorInterface.sol";
import {ISwapSteward} from "src/finance/interfaces/ISwapSteward.sol";

/**
 * @title SwapSteward
 * @author efecarranza  (Tokenlogic)
 * @notice Facilitates token swaps on behalf of the DAO Treasury through Composable CoW.
 * Same role, budget, pair and oracle model as MainnetSwapSteward, without Milkman.
 * The receiver of every swap is the Collector. Only one swap per fromToken can be pending.
 */
contract SwapSteward is ISwapSteward, OwnableWithGuardian, Multicall, RescuableBase, ERC1271Forwarder {
  /// @inheritdoc ISwapSteward
  uint256 public constant MAX_SLIPPAGE = 10_00; // 10%

  /// @inheritdoc ISwapSteward
  address public immutable COLLECTOR;

  /// @inheritdoc ISwapSteward
  address public immutable MARKET_ORDER_HANDLER;

  /// @inheritdoc ISwapSteward
  address public immutable LIMIT_ORDER_HANDLER;

  /// @inheritdoc ISwapSteward
  address public immutable TWAP_HANDLER;

  /// @inheritdoc ISwapSteward
  address public immutable VAULT_RELAYER;

  /// @inheritdoc ISwapSteward
  bytes32 public immutable APP_DATA;

  /// @inheritdoc ISwapSteward
  mapping(address fromToken => mapping(address toToken => bool isApproved)) public swapApprovedToken;

  /// @inheritdoc ISwapSteward
  mapping(address token => address oracle) public priceOracle;

  /// @inheritdoc ISwapSteward
  mapping(address token => uint256 budget) public tokenBudget;

  /// @inheritdoc ISwapSteward
  mapping(address fromToken => bytes32 orderHash) public pendingOrder;

  constructor(
    address initialOwner,
    address initialGuardian,
    address collector,
    address composableCow,
    address marketOrderHandler,
    address limitOrderHandler,
    address twapHandler,
    address vaultRelayer,
    bytes32 appData
  ) OwnableWithGuardian(initialOwner, initialGuardian) ERC1271Forwarder(composableCow) {
    COLLECTOR = collector;
    MARKET_ORDER_HANDLER = marketOrderHandler;
    LIMIT_ORDER_HANDLER = limitOrderHandler;
    TWAP_HANDLER = twapHandler;
    VAULT_RELAYER = vaultRelayer;
    APP_DATA = appData;
  }

  /// @inheritdoc ISwapSteward
  function swap(address, address, uint256, uint256) external onlyOwnerOrGuardian returns (bytes32) {}

  /// @inheritdoc ISwapSteward
  function limitSwap(address, address, uint256, uint256) external onlyOwnerOrGuardian returns (bytes32) {}

  /// @inheritdoc ISwapSteward
  function twapSwap(address, address, uint256, uint256, uint256, uint256, uint256, uint256)
    external
    onlyOwnerOrGuardian
    returns (bytes32)
  {}

  /// @inheritdoc ISwapSteward
  function cancelSwap(address) external onlyOwnerOrGuardian {}

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

    swapApprovedToken[fromToken][toToken] = allowed;

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
  function getExpectedOut(uint256, address, address) external pure returns (uint256) {}

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

  function _transferTokensIn(address fromToken, uint256 amount) internal {
    ICollector(COLLECTOR).transfer(IERC20(fromToken), address(this), amount);
  }

  /// @dev Internal function to perform common validation of swaps
  function _validateCommon(address fromToken, address toToken, uint256 amount) internal view {
    if (amount == 0) revert InvalidZeroAmount();
    if (!swapApprovedToken[fromToken][toToken]) {
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
