// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapSteward} from "src/finance/swap/SwapSteward.sol";
import {SwapStewardTestUtils} from "tests/finance/swap/SwapStewardTestUtils.sol";

/**
 * @dev Invariant handler of the SwapSteward custody and budget suite. Drives the steward as its owner and guardian
 * through swap, twapSwap, cancelSwap, budget changes, donations to open escrows and time. Settlement is out of scope:
 * no order is ever filled. Every input is bounded so that no action reverts, and an action with no valid input returns
 * early. Ghost state is computed from the action inputs, except the owner max-amount path, which reads the Collector
 * token balance (a raw token read, not a steward value) that invariant_custodyConservation pins.
 */
contract SwapStewardHandler is SwapStewardTestUtils {
  using SafeERC20 for IERC20;

  error RequestEventMissing();

  struct Setup {
    SwapSteward steward;
    address executor;
    address collector;
    address fromToken;
    address toToken;
    address otherToken;
    uint256 initialFromBudget;
    uint256 initialOtherBudget;
    uint256 initialFromBalance;
    uint256 initialOtherBalance;
  }

  /// @dev Ghost record of one SwapEscrow clone, created from the steward's request event
  struct Escrow {
    address sellToken;
    bytes32 orderHash;
    uint256 funded;
    uint256 donated;
    bool open;
  }

  struct Twap {
    address sellToken;
    address buyToken;
    uint256 partSellAmount;
    uint256 minPartLimit;
    uint256 numParts;
    uint256 partDuration;
    uint256 span;
  }

  uint256 internal constant MAX_TWAP_PARTS = 10;
  uint256 internal constant MAX_TWAP_MIN_PART_LIMIT = 1e24;
  uint256 internal constant MAX_WARP = 7 days;
  uint256 internal constant SELL_TOKEN_SHIFT = 1;
  uint256 internal constant BUY_TOKEN_SHIFT = 2;
  uint256 internal constant MAX_AMOUNT_SHIFT = 3;

  /// @dev Collector balance of each sell token at the start of the campaign
  mapping(address token => uint256 balance) public initialCollectorBalance;
  /// @dev Budget added to each sell token: the initial budget plus every increaseTokenBudget input
  mapping(address token => uint256 amount) public ghostIncreased;
  /// @dev Budget removed from each sell token by decreaseTokenBudget inputs
  mapping(address token => uint256 amount) public ghostDecreased;
  /// @dev Sell token amount funded into escrows by guardian swaps, which consume the budget
  mapping(address token => uint256 amount) public ghostGuardianSpent;
  /// @dev Sell token amount funded into escrows by owner swaps, which skip the budget
  mapping(address token => uint256 amount) public ghostOwnerSpent;
  /// @dev Sell token amount donated to escrows that were open at the time
  mapping(address token => uint256 amount) public ghostDonated;

  uint256 public swapCount;
  uint256 public twapCount;
  uint256 public cancelCount;
  uint256 public donationCount;

  address[] internal escrowList;
  mapping(address escrow => Escrow record) internal records;

  constructor(Setup memory setup) {
    steward = setup.steward;
    executor = setup.executor;
    collector = setup.collector;
    fromToken = setup.fromToken;
    toToken = setup.toToken;
    otherToken = setup.otherToken;

    initialCollectorBalance[fromToken] = setup.initialFromBalance;
    initialCollectorBalance[otherToken] = setup.initialOtherBalance;
    ghostIncreased[fromToken] = setup.initialFromBudget;
    ghostIncreased[otherToken] = setup.initialOtherBudget;
  }

  function escrowCount() external view returns (uint256) {
    return escrowList.length;
  }

  function escrowAt(uint256 index) external view returns (address escrow, Escrow memory record) {
    escrow = escrowList[index];
    record = records[escrow];
  }

  function swap(uint256 seed, uint256 amountSeed, uint256 slippageSeed) external {
    address caller = _caller(seed);
    address sellToken = _sellToken(seed >> SELL_TOKEN_SHIFT);
    (uint256 amount, uint256 argument) = _swapAmount(caller, sellToken, amountSeed, (seed >> MAX_AMOUNT_SHIFT) & 1 == 1);
    if (amount == 0) return;

    vm.recordLogs();
    vm.prank(caller);
    steward.swap(
      sellToken, _buyToken(sellToken, seed >> BUY_TOKEN_SHIFT), argument, bound(slippageSeed, 0, MAX_SLIPPAGE)
    );

    _trackRequest(caller, sellToken, amount, ISwapSteward.SwapRequested.selector);
    swapCount++;
  }

  function twapSwap(
    uint256 seed,
    uint256 numPartsSeed,
    uint256 partAmountSeed,
    uint256 minPartLimitSeed,
    uint256 partDurationSeed,
    uint256 spanSeed
  ) external {
    address caller = _caller(seed);
    address sellToken = _sellToken(seed >> SELL_TOKEN_SHIFT);
    (, uint256 limit) = _limits(caller, sellToken);
    if (limit < 2) return;

    Twap memory twap = Twap({
      sellToken: sellToken,
      buyToken: _buyToken(sellToken, seed >> BUY_TOKEN_SHIFT),
      partSellAmount: 0,
      minPartLimit: bound(minPartLimitSeed, 1, MAX_TWAP_MIN_PART_LIMIT),
      numParts: bound(numPartsSeed, 2, limit < MAX_TWAP_PARTS ? limit : MAX_TWAP_PARTS),
      partDuration: bound(partDurationSeed, 1, TWAP_MAX_PART_DURATION),
      span: 0
    });
    twap.partSellAmount = bound(partAmountSeed, 1, limit / twap.numParts);
    twap.span = bound(spanSeed, 0, twap.partDuration);

    vm.recordLogs();
    vm.prank(caller);
    _requestTwap(twap);

    _trackRequest(caller, sellToken, twap.partSellAmount * twap.numParts, ISwapSteward.TWAPSwapRequested.selector);
    twapCount++;
  }

  function cancelSwap(uint256 seed, uint256 escrowSeed) external {
    (address escrow, bool found) = _openEscrow(escrowSeed);
    if (!found) return;

    vm.prank(_caller(seed));
    steward.cancelSwap(escrow);

    records[escrow].open = false;
    cancelCount++;
  }

  function increaseTokenBudget(uint256 seed, uint256 amountSeed) external {
    address token = _sellToken(seed);
    uint256 amount = bound(amountSeed, 0, initialCollectorBalance[token]);

    vm.prank(executor);
    steward.increaseTokenBudget(token, amount);

    ghostIncreased[token] += amount;
  }

  function decreaseTokenBudget(uint256 seed, uint256 amountSeed) external {
    address token = _sellToken(seed);
    uint256 amount = bound(amountSeed, 0, _budget(token));

    vm.prank(executor);
    steward.decreaseTokenBudget(token, amount);

    ghostDecreased[token] += amount;
  }

  function donateToEscrow(uint256 escrowSeed, uint256 amountSeed) external {
    (address escrow, bool found) = _openEscrow(escrowSeed);
    if (!found) return;

    address token = records[escrow].sellToken;
    uint256 amount = bound(amountSeed, 1, initialCollectorBalance[token]);

    deal(token, address(this), amount);
    IERC20(token).safeTransfer(escrow, amount);

    records[escrow].donated += amount;
    ghostDonated[token] += amount;
    donationCount++;
  }

  function warpForward(uint256 secondsSeed) external {
    vm.warp(block.timestamp + bound(secondsSeed, 1, MAX_WARP));
  }

  function _requestTwap(Twap memory twap) internal {
    steward.twapSwap(
      twap.sellToken,
      twap.buyToken,
      twap.partSellAmount,
      twap.minPartLimit,
      0,
      twap.numParts,
      twap.partDuration,
      twap.span
    );
  }

  function _caller(uint256 seed) internal view returns (address) {
    return seed & 1 == 0 ? executor : guardian;
  }

  function _sellToken(uint256 seed) internal view returns (address) {
    return seed & 1 == 0 ? fromToken : otherToken;
  }

  function _buyToken(address sellToken, uint256 seed) internal view returns (address) {
    if (seed & 1 == 0) return toToken;
    return sellToken == fromToken ? otherToken : fromToken;
  }

  function _budget(address token) internal view returns (uint256) {
    return ghostIncreased[token] - ghostDecreased[token] - ghostGuardianSpent[token];
  }

  function _limits(address caller, address sellToken) internal view returns (uint256 maxAmount, uint256 limit) {
    uint256 balance = IERC20(sellToken).balanceOf(collector);
    maxAmount = caller == executor ? balance : _budget(sellToken);
    limit = maxAmount < balance ? maxAmount : balance;
  }

  function _swapAmount(address caller, address sellToken, uint256 amountSeed, bool useMax)
    internal
    view
    returns (uint256 amount, uint256 argument)
  {
    (uint256 maxAmount, uint256 limit) = _limits(caller, sellToken);
    if (limit == 0) return (0, 0);

    if (useMax && maxAmount == limit) return (maxAmount, type(uint256).max);

    amount = bound(amountSeed, 1, limit);
    return (amount, amount);
  }

  function _openEscrow(uint256 seed) internal view returns (address escrow, bool found) {
    uint256 openCount;
    for (uint256 i; i < escrowList.length; ++i) {
      if (records[escrowList[i]].open) openCount++;
    }
    if (openCount == 0) return (address(0), false);

    uint256 target = seed % openCount;
    for (uint256 i; i < escrowList.length; ++i) {
      if (!records[escrowList[i]].open) continue;
      if (target == 0) return (escrowList[i], true);
      target--;
    }
  }

  function _trackRequest(address caller, address sellToken, uint256 funded, bytes32 requestTopic) internal {
    Vm.Log[] memory logs = vm.getRecordedLogs();
    for (uint256 i; i < logs.length; ++i) {
      if (logs[i].emitter != address(steward) || logs[i].topics[0] != requestTopic) continue;

      address escrow = address(uint160(uint256(logs[i].topics[1])));
      records[escrow] = Escrow({
        sellToken: sellToken, orderHash: abi.decode(logs[i].data, (bytes32)), funded: funded, donated: 0, open: true
      });
      escrowList.push(escrow);

      if (caller == executor) {
        ghostOwnerSpent[sellToken] += funded;
      } else {
        ghostGuardianSpent[sellToken] += funded;
      }
      return;
    }
    revert RequestEventMissing();
  }
}
