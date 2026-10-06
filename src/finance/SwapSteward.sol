// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";
import {RescuableBase} from "solidity-utils/contracts/utils/RescuableBase.sol";

import {ERC1271Forwarder} from "src/finance/ERC1271Forwarder.sol";
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
  function increaseTokenBudget(address, uint256) external onlyOwner {}

  /// @inheritdoc ISwapSteward
  function decreaseTokenBudget(address, uint256) external onlyOwner {}

  /// @inheritdoc ISwapSteward
  function setSwappablePair(address, address, bool) external onlyOwner {}

  /// @inheritdoc ISwapSteward
  function setTokenOracle(address, address) external onlyOwner {}

  /// @inheritdoc ISwapSteward
  function rescueToken(address) external onlyOwnerOrGuardian {}

  /// @inheritdoc ISwapSteward
  function rescueToken(address, uint256) external onlyOwnerOrGuardian {}

  /// @inheritdoc ISwapSteward
  function getExpectedOut(uint256, address, address) external pure returns (uint256) {}

  /// @inheritdoc RescuableBase
  function maxRescue(address token) public view override(RescuableBase) returns (uint256) {
    return IERC20(token).balanceOf(address(this));
  }
}
