// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {OracleMarketOrder} from "src/finance/OracleMarketOrder.sol";
import {IConditionalOrder} from "src/finance/interfaces/IConditionalOrder.sol";
import {GPv2Order} from "src/finance/libraries/GPv2Order.sol";
import {MockAggregator} from "tests/finance/OracleMocks.sol";

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
 * command: forge test -vvv --match-path tests/finance/OracleMarketOrder.t.sol
 */
contract OracleMarketOrderTest is Test {
  uint32 internal constant GRACE_PERIOD = 3600;
  uint256 internal constant NOW = 1_000_000;
  uint32 internal constant VALID_UNTIL = uint32(NOW + 1 days);
  uint256 internal constant SELL_AMOUNT = 1e18;
  address internal constant OWNER = address(0x0FFE);
  address internal constant RECEIVER = address(0xC011);
  bytes32 internal constant APP_DATA = keccak256("appData");
  uint256 internal constant EXPECTED_BUY_AMOUNT = 99e6;

  OracleMarketOrder public handler;
  MockSequencerFeed public sequencerFeed;

  function setUp() public {
    vm.warp(NOW);
    handler = new OracleMarketOrder();
    sequencerFeed = new MockSequencerFeed();
  }

  function _staticInput() internal returns (bytes memory) {
    return _staticInput(100e8, 1e8);
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
    address fromToken = address(deployMockERC20("From", "FROM", 18));
    deal(fromToken, OWNER, ownerBalance);
    return OracleMarketOrder.Data({
      fromToken: fromToken,
      toToken: address(deployMockERC20("To", "TO", 6)),
      fromOracle: address(new MockAggregator(fromPrice)),
      toOracle: address(new MockAggregator(toPrice)),
      receiver: RECEIVER,
      sellAmount: SELL_AMOUNT,
      slippage: 100,
      appData: APP_DATA,
      validUntil: VALID_UNTIL,
      sequencerUptimeFeed: address(sequencerFeed),
      sequencerGracePeriod: GRACE_PERIOD
    });
  }

  function _expectPoll(bytes memory err) internal {
    bytes memory input = _staticInput();
    vm.expectRevert(err);
    handler.getTradeableOrder(OWNER, address(0), bytes32(0), input, "");
  }

  function test_getTradeableOrder() public {
    sequencerFeed.set(0, NOW - GRACE_PERIOD - 1);
    OracleMarketOrder.Data memory data = _data(100e8, 1e8, SELL_AMOUNT);

    GPv2Order.Data memory order = handler.getTradeableOrder(OWNER, address(0), bytes32(0), abi.encode(data), "");

    assertEq(address(order.sellToken), data.fromToken);
    assertEq(address(order.buyToken), data.toToken);
    assertEq(order.receiver, RECEIVER);
    assertEq(order.sellAmount, SELL_AMOUNT);
    assertEq(order.buyAmount, EXPECTED_BUY_AMOUNT);
    assertEq(order.validTo, VALID_UNTIL);
    assertEq(order.appData, APP_DATA);
    assertEq(order.feeAmount, 0);
    assertEq(order.kind, keccak256("sell"));
    assertFalse(order.partiallyFillable);
    assertEq(order.sellTokenBalance, keccak256("erc20"));
    assertEq(order.buyTokenBalance, keccak256("erc20"));
  }

  function test_getTradeableOrder_validToIsValidUntil() public {
    sequencerFeed.set(0, NOW - GRACE_PERIOD - 1);
    bytes memory input = _staticInput();
    vm.warp(VALID_UNTIL);
    assertEq(handler.getTradeableOrder(OWNER, address(0), bytes32(0), input, "").validTo, VALID_UNTIL);
  }

  function test_getTradeableOrder_revertsWith_OrderNotValid_expired() public {
    sequencerFeed.set(0, NOW - GRACE_PERIOD - 1);
    bytes memory input = _staticInput();
    vm.warp(uint256(VALID_UNTIL) + 1);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "order expired"));
    handler.getTradeableOrder(OWNER, address(0), bytes32(0), input, "");
  }

  function test_getTradeableOrder_revertsWith_OrderNotValid_insufficientBalance() public {
    sequencerFeed.set(0, NOW - GRACE_PERIOD - 1);
    bytes memory input = _staticInput(100e8, 1e8, SELL_AMOUNT - 1);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "insufficient balance"));
    handler.getTradeableOrder(OWNER, address(0), bytes32(0), input, "");
  }

  function test_getTradeableOrder_revertsWith_OrderNotValid_zeroBuyAmount() public {
    sequencerFeed.set(0, NOW - GRACE_PERIOD - 1);
    bytes memory input = _staticInput(1, 1e8 * 1e8, SELL_AMOUNT);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "zero buy amount"));
    handler.getTradeableOrder(OWNER, address(0), bytes32(0), input, "");
  }

  function test_getTradeableOrder_revertsWith_PollTryNextBlock_fromOraclePriceZeroOrNegative() public {
    int256[2] memory badAnswers = [int256(0), int256(-1)];
    for (uint256 i; i < badAnswers.length; i++) {
      _expectInvalidOraclePrice(badAnswers[i], 1e8);
    }
  }

  function test_getTradeableOrder_revertsWith_PollTryNextBlock_toOraclePriceZeroOrNegative() public {
    int256[2] memory badAnswers = [int256(0), int256(-1)];
    for (uint256 i; i < badAnswers.length; i++) {
      _expectInvalidOraclePrice(100e8, badAnswers[i]);
    }
  }

  function test_getTradeableOrder_revertsWith_PollTryNextBlock_sequencerDown() public {
    sequencerFeed.set(1, NOW - 1);
    _expectPoll(abi.encodeWithSelector(IConditionalOrder.PollTryNextBlock.selector, "sequencer down"));
  }

  function test_getTradeableOrder_revertsWith_PollTryAtEpoch_gracePeriodNotOver() public {
    uint256 startedAt = NOW - GRACE_PERIOD;
    sequencerFeed.set(0, startedAt);
    _expectPoll(
      abi.encodeWithSelector(
        IConditionalOrder.PollTryAtEpoch.selector, startedAt + GRACE_PERIOD + 1, "sequencer grace period not over"
      )
    );
  }

  function test_getTradeableOrder_revertsWith_PollTryNextBlock_sequencerStartedAtZero() public {
    sequencerFeed.set(0, 0);
    _expectPoll(abi.encodeWithSelector(IConditionalOrder.PollTryNextBlock.selector, "invalid sequencer timestamp"));
  }

  function test_getTradeableOrder_revertsWith_PollTryNextBlock_sequencerStartedAtInFuture() public {
    sequencerFeed.set(0, NOW + 1);
    _expectPoll(abi.encodeWithSelector(IConditionalOrder.PollTryNextBlock.selector, "invalid sequencer timestamp"));
  }

  function test_getTradeableOrder_noSequencerFeed() public {
    OracleMarketOrder.Data memory data = _data(100e8, 1e8, SELL_AMOUNT);
    data.sequencerUptimeFeed = address(0);

    GPv2Order.Data memory order = handler.getTradeableOrder(OWNER, address(0), bytes32(0), abi.encode(data), "");

    assertEq(order.buyAmount, EXPECTED_BUY_AMOUNT);
  }

  function _expectInvalidOraclePrice(int256 fromPrice, int256 toPrice) internal {
    sequencerFeed.set(0, NOW - GRACE_PERIOD - 1);
    bytes memory input = _staticInput(fromPrice, toPrice);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.PollTryNextBlock.selector, "invalid oracle price"));
    handler.getTradeableOrder(OWNER, address(0), bytes32(0), input, "");
  }
}
