// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {OracleMarketOrder} from "src/finance/OracleMarketOrder.sol";
import {IConditionalOrder} from "src/finance/interfaces/IConditionalOrder.sol";

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

contract MockAggregator {
  int256 public latestAnswer;
  uint8 public constant decimals = 8;

  constructor(int256 answer_) {
    latestAnswer = answer_;
  }
}

contract MockToken {
  uint8 public decimals;
  mapping(address => uint256) public balanceOf;

  constructor(uint8 decimals_) {
    decimals = decimals_;
  }

  function setBalance(address account, uint256 amount) external {
    balanceOf[account] = amount;
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
    MockToken fromToken = new MockToken(18);
    fromToken.setBalance(OWNER, ownerBalance);
    return abi.encode(
      OracleMarketOrder.Data({
        fromToken: address(fromToken),
        toToken: address(new MockToken(6)),
        fromOracle: address(new MockAggregator(fromPrice)),
        toOracle: address(new MockAggregator(toPrice)),
        receiver: address(0xC011),
        sellAmount: SELL_AMOUNT,
        slippage: 100,
        appData: bytes32(0),
        validUntil: VALID_UNTIL,
        sequencerUptimeFeed: address(sequencerFeed),
        sequencerGracePeriod: GRACE_PERIOD
      })
    );
  }

  function _expectPoll(bytes memory err) internal {
    bytes memory input = _staticInput();
    vm.expectRevert(err);
    handler.getTradeableOrder(OWNER, address(0), bytes32(0), input, "");
  }

  function test_supportsInterface() public {}

  function test_getTradeableOrder() public {}

  function test_getTradeableOrder_decimals() public {}

  function test_getTradeableOrder_receiverIsStaticInputReceiver() public {}

  function test_getTradeableOrder_feeAmountIsZero() public {}

  function test_getTradeableOrder_appDataPinned() public {}

  function test_fuzz_getTradeableOrder_slippage() public {}

  function test_getTradeableOrder_slippageCap() public {}

  function test_getTradeableOrder_validToIsValidUntil() public {
    sequencerFeed.set(0, NOW - GRACE_PERIOD - 1);
    bytes memory input = _staticInput();
    vm.warp(VALID_UNTIL);
    assertEq(handler.getTradeableOrder(OWNER, address(0), bytes32(0), input, "").validTo, VALID_UNTIL);
  }

  function test_getTradeableOrder_revertsIf_expired() public {
    sequencerFeed.set(0, NOW - GRACE_PERIOD - 1);
    bytes memory input = _staticInput();
    vm.warp(uint256(VALID_UNTIL) + 1);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "order expired"));
    handler.getTradeableOrder(OWNER, address(0), bytes32(0), input, "");
  }

  function test_getTradeableOrder_revertsIf_insufficientBalance() public {
    sequencerFeed.set(0, NOW - GRACE_PERIOD - 1);
    bytes memory input = _staticInput(100e8, 1e8, SELL_AMOUNT - 1);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "insufficient balance"));
    handler.getTradeableOrder(OWNER, address(0), bytes32(0), input, "");
  }

  function test_getTradeableOrder_revertsIf_invalidPrice() public {}

  function test_getTradeableOrder_revertsIf_zeroBuyAmount() public {}

  function _expectInvalidOraclePrice(int256 fromPrice, int256 toPrice) internal {
    sequencerFeed.set(0, NOW - GRACE_PERIOD - 1);
    bytes memory input = _staticInput(fromPrice, toPrice);
    vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.PollTryNextBlock.selector, "invalid oracle price"));
    handler.getTradeableOrder(OWNER, address(0), bytes32(0), input, "");
  }

  function test_getTradeableOrder_revertsIf_fromOraclePriceZero() public {
    _expectInvalidOraclePrice(0, 1e8);
  }

  function test_getTradeableOrder_revertsIf_toOraclePriceNegative() public {
    _expectInvalidOraclePrice(100e8, -1);
  }

  function test_getTradeableOrder_revertsIf_sequencerDown() public {
    sequencerFeed.set(1, NOW - 1);
    _expectPoll(abi.encodeWithSelector(IConditionalOrder.PollTryNextBlock.selector, "sequencer down"));
  }

  function test_getTradeableOrder_revertsIf_gracePeriodNotOver() public {
    uint256 startedAt = NOW - GRACE_PERIOD;
    sequencerFeed.set(0, startedAt);
    _expectPoll(
      abi.encodeWithSelector(
        IConditionalOrder.PollTryAtEpoch.selector, startedAt + GRACE_PERIOD + 1, "sequencer grace period not over"
      )
    );
  }

  function test_getTradeableOrder_revertsIf_sequencerStartedAtZero() public {
    sequencerFeed.set(0, 0);
    _expectPoll(abi.encodeWithSelector(IConditionalOrder.PollTryNextBlock.selector, "invalid sequencer timestamp"));
  }

  function test_getTradeableOrder_revertsIf_sequencerStartedAtInFuture() public {
    sequencerFeed.set(0, NOW + 1);
    _expectPoll(abi.encodeWithSelector(IConditionalOrder.PollTryNextBlock.selector, "invalid sequencer timestamp"));
  }

  function test_getTradeableOrder_noSequencerFeed() public {}

  function test_verify() public {}

  function test_verify_revertsIf_invalidHash() public {}

  function test_verify_revertsIf_afterOracleRoundChange() public {}
}
