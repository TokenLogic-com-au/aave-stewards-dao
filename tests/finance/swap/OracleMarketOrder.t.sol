// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {
  OracleMarketOrder,
  SEQUENCER_DOWN,
  INVALID_SEQUENCER_TIMESTAMP,
  SEQUENCER_GRACE_PERIOD_NOT_OVER,
  INVALID_ORACLE_PRICE,
  ZERO_BUY_AMOUNT,
  ORDER_EXPIRED,
  INSUFFICIENT_BALANCE
} from "src/finance/swap/OracleMarketOrder.sol";
import {IConditionalOrder} from "composable-cow/interfaces/IConditionalOrder.sol";
import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {MockAggregator, badAnswers} from "tests/finance/swap/OracleMocks.sol";

contract MockSequencerFeed {
  int256 public answer;
  uint256 public startedAt;

  function set(int256 answer_, uint256 startedAt_) external {
    answer = answer_;
    startedAt = startedAt_;
  }

  function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
    return (0, answer, startedAt, 0, 0);
  }
}

/**
 * @dev Test for OracleMarketOrder handler
 * command: forge test -vvv --match-path tests/finance/swap/OracleMarketOrder.t.sol
 */
contract OracleMarketOrderTest is Test {
  uint256 internal constant GRACE_PERIOD = 1 hours;
  uint256 internal constant NOW = 1_000_000;
  uint32 internal constant VALID_TO = uint32(NOW + 1 days);
  uint256 internal constant SELL_AMOUNT = 1e18;
  address internal constant OWNER = address(0x0FFE);
  address internal constant RECEIVER = address(0xC011);
  bytes32 internal constant APP_DATA = keccak256("appData");
  uint8 internal constant FROM_DECIMALS = 18;
  uint8 internal constant TO_DECIMALS = 6;
  int256 internal constant FROM_PRICE = 100e8;
  int256 internal constant TO_PRICE = 1e8;
  uint256 internal constant SLIPPAGE = 100;
  /// @dev Hand-computed: 100e6 expected out minus 1% (SLIPPAGE) = 99e6
  uint256 internal constant EXPECTED_BUY_AMOUNT = 99e6;

  OracleMarketOrder public handler;
  MockSequencerFeed public sequencerFeed;

  function setUp() public {
    vm.warp(NOW);
    handler = new OracleMarketOrder();
    sequencerFeed = new MockSequencerFeed();
  }

  function _staticInput() internal returns (bytes memory) {
    return _staticInput(FROM_PRICE, TO_PRICE);
  }

  function _staticInput(int256 fromPrice, int256 toPrice) internal returns (bytes memory) {
    return _staticInput(fromPrice, toPrice, SELL_AMOUNT);
  }

  function _staticInput(int256 fromPrice, int256 toPrice, uint256 ownerBalance) internal returns (bytes memory) {
    return abi.encode(_data(fromPrice, toPrice, ownerBalance));
  }

  function _data(int256 fromPrice, int256 toPrice, uint256 ownerBalance)
    internal
    returns (OracleMarketOrder.Data memory)
  {
    address fromToken = address(deployMockERC20("From", "FROM", FROM_DECIMALS));
    deal(fromToken, OWNER, ownerBalance);
    return OracleMarketOrder.Data({
      fromToken: fromToken,
      toToken: address(deployMockERC20("To", "TO", TO_DECIMALS)),
      fromOracle: address(new MockAggregator(fromPrice)),
      toOracle: address(new MockAggregator(toPrice)),
      receiver: RECEIVER,
      sellAmount: SELL_AMOUNT,
      slippage: SLIPPAGE,
      appData: APP_DATA,
      validTo: VALID_TO,
      sequencerUptimeFeed: address(sequencerFeed),
      sequencerGracePeriod: GRACE_PERIOD
    });
  }

  function _expectPoll(bytes memory err) internal {
    bytes memory input = _staticInput();
    vm.expectRevert(err);
    handler.getTradeableOrder(OWNER, address(0), bytes32(0), input, "");
  }

  function test_reasonStrings() public pure {
    assertEq(SEQUENCER_DOWN, "sequencer down");
    assertEq(INVALID_SEQUENCER_TIMESTAMP, "invalid sequencer timestamp");
    assertEq(SEQUENCER_GRACE_PERIOD_NOT_OVER, "sequencer grace period not over");
    assertEq(INVALID_ORACLE_PRICE, "invalid oracle price");
    assertEq(ZERO_BUY_AMOUNT, "zero buy amount");
    assertEq(ORDER_EXPIRED, "order expired");
    assertEq(INSUFFICIENT_BALANCE, "insufficient balance");
  }

  function test_getTradeableOrder() public {
    sequencerFeed.set(0, NOW - GRACE_PERIOD - 1);
    OracleMarketOrder.Data memory data = _data(FROM_PRICE, TO_PRICE, SELL_AMOUNT);

    GPv2Order.Data memory order = handler.getTradeableOrder(OWNER, address(0), bytes32(0), abi.encode(data), "");

    assertEq(address(order.sellToken), data.fromToken);
    assertEq(address(order.buyToken), data.toToken);
    assertEq(order.receiver, RECEIVER);
    assertEq(order.sellAmount, SELL_AMOUNT);
    assertEq(order.buyAmount, EXPECTED_BUY_AMOUNT);
    assertEq(order.validTo, VALID_TO);
    assertEq(order.appData, APP_DATA);
    assertEq(order.feeAmount, 0);
    assertEq(order.kind, GPv2Order.KIND_SELL);
    assertFalse(order.partiallyFillable);
    assertEq(order.sellTokenBalance, GPv2Order.BALANCE_ERC20);
    assertEq(order.buyTokenBalance, GPv2Order.BALANCE_ERC20);
  }

  function test_getTradeableOrder_notExpiredAtValidTo() public {
    sequencerFeed.set(0, NOW - GRACE_PERIOD - 1);
    bytes memory input = _staticInput();
    vm.warp(VALID_TO);
    assertEq(handler.getTradeableOrder(OWNER, address(0), bytes32(0), input, "").validTo, VALID_TO);
  }

  function test_getTradeableOrder_revertsWith_OrderNotValid_expired() public {
    sequencerFeed.set(0, NOW - GRACE_PERIOD - 1);
    bytes memory input = _staticInput();
    vm.warp(uint256(VALID_TO) + 1);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, ORDER_EXPIRED));
    handler.getTradeableOrder(OWNER, address(0), bytes32(0), input, "");
  }

  function test_getTradeableOrder_revertsWith_OrderNotValid_insufficientBalance() public {
    sequencerFeed.set(0, NOW - GRACE_PERIOD - 1);
    bytes memory input = _staticInput(FROM_PRICE, TO_PRICE, SELL_AMOUNT - 1);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, INSUFFICIENT_BALANCE));
    handler.getTradeableOrder(OWNER, address(0), bytes32(0), input, "");
  }

  function test_getTradeableOrder_revertsWith_OrderNotValid_zeroBuyAmount() public {
    sequencerFeed.set(0, NOW - GRACE_PERIOD - 1);
    bytes memory input = _staticInput(1, int256(10 ** TO_DECIMALS), SELL_AMOUNT);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, ZERO_BUY_AMOUNT));
    handler.getTradeableOrder(OWNER, address(0), bytes32(0), input, "");
  }

  function test_getTradeableOrder_revertsWith_PollTryNextBlock_fromOraclePriceZeroOrNegative() public {
    int256[2] memory answers = badAnswers();
    for (uint256 i; i < answers.length; i++) {
      _expectInvalidOraclePrice(answers[i], TO_PRICE);
    }
  }

  function test_getTradeableOrder_revertsWith_PollTryNextBlock_toOraclePriceZeroOrNegative() public {
    int256[2] memory answers = badAnswers();
    for (uint256 i; i < answers.length; i++) {
      _expectInvalidOraclePrice(FROM_PRICE, answers[i]);
    }
  }

  function test_getTradeableOrder_revertsWith_PollTryNextBlock_sequencerDown() public {
    sequencerFeed.set(1, NOW - 1);
    _expectPoll(abi.encodeWithSelector(IConditionalOrder.PollTryNextBlock.selector, SEQUENCER_DOWN));
  }

  function test_getTradeableOrder_revertsWith_PollTryAtEpoch_gracePeriodNotOver() public {
    uint256 startedAt = NOW - GRACE_PERIOD;
    sequencerFeed.set(0, startedAt);
    _expectPoll(
      abi.encodeWithSelector(
        IConditionalOrder.PollTryAtEpoch.selector, startedAt + GRACE_PERIOD + 1, SEQUENCER_GRACE_PERIOD_NOT_OVER
      )
    );
  }

  function test_getTradeableOrder_revertsWith_PollTryNextBlock_sequencerStartedAtZero() public {
    sequencerFeed.set(0, 0);
    _expectPoll(abi.encodeWithSelector(IConditionalOrder.PollTryNextBlock.selector, INVALID_SEQUENCER_TIMESTAMP));
  }

  function test_getTradeableOrder_revertsWith_PollTryNextBlock_sequencerStartedAtInFuture() public {
    sequencerFeed.set(0, NOW + 1);
    _expectPoll(abi.encodeWithSelector(IConditionalOrder.PollTryNextBlock.selector, INVALID_SEQUENCER_TIMESTAMP));
  }

  function test_getTradeableOrder_noSequencerFeed() public {
    OracleMarketOrder.Data memory data = _data(FROM_PRICE, TO_PRICE, SELL_AMOUNT);
    data.sequencerUptimeFeed = address(0);

    GPv2Order.Data memory order = handler.getTradeableOrder(OWNER, address(0), bytes32(0), abi.encode(data), "");

    assertEq(order.buyAmount, EXPECTED_BUY_AMOUNT);
  }

  function _expectInvalidOraclePrice(int256 fromPrice, int256 toPrice) internal {
    sequencerFeed.set(0, NOW - GRACE_PERIOD - 1);
    bytes memory input = _staticInput(fromPrice, toPrice);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.PollTryNextBlock.selector, INVALID_ORACLE_PRICE));
    handler.getTradeableOrder(OWNER, address(0), bytes32(0), input, "");
  }
}
