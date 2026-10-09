// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "cowprotocol/contracts/interfaces/IERC20.sol";
import {BaseConditionalOrder} from "composable-cow/BaseConditionalOrder.sol";
import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {IConditionalOrder} from "composable-cow/interfaces/IConditionalOrder.sol";
import {AggregatorInterface} from "aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol";
import {OracleMath} from "src/finance/swap/libraries/OracleMath.sol";

/**
 * @title OracleMarketOrder
 * @author halaprix
 * @notice Conditional order handler that prices a market swap from Chainlink oracles at execution time
 */
contract OracleMarketOrder is BaseConditionalOrder {
  string internal constant SEQUENCER_DOWN = "sequencer down";
  string internal constant INVALID_SEQUENCER_TIMESTAMP = "invalid sequencer timestamp";
  string internal constant SEQUENCER_GRACE_PERIOD_NOT_OVER = "sequencer grace period not over";
  string internal constant INVALID_ORACLE_PRICE = "invalid oracle price";
  string internal constant ZERO_BUY_AMOUNT = "zero buy amount";
  string internal constant ORDER_EXPIRED = "order expired";
  string internal constant INSUFFICIENT_BALANCE = "insufficient balance";

  /// @notice Static input of the conditional order
  /// @param fromToken Token being sold
  /// @param toToken Token being bought
  /// @param fromOracle Oracle pricing fromToken
  /// @param toOracle Oracle pricing toToken
  /// @param receiver Receiver of the bought token, the Collector
  /// @param sellAmount Amount of fromToken to sell
  /// @param slippage Allowed slippage against the oracle price, where 100_00 is equal to 100%
  /// @param appData appData pinned on the order
  /// @param validUntil Last timestamp at which the order can be settled, used as `validTo`
  /// @param sequencerUptimeFeed Chainlink L2 sequencer uptime feed, zero on chains without one
  /// @param sequencerGracePeriod Seconds the sequencer must be up before orders are generated
  struct Data {
    address fromToken;
    address toToken;
    address fromOracle;
    address toOracle;
    address receiver;
    uint256 sellAmount;
    uint256 slippage;
    bytes32 appData;
    uint32 validUntil;
    address sequencerUptimeFeed;
    uint32 sequencerGracePeriod;
  }

  /// @inheritdoc BaseConditionalOrder
  function getTradeableOrder(address owner, address, bytes32, bytes calldata staticInput, bytes calldata)
    public
    view
    override
    returns (GPv2Order.Data memory)
  {
    Data memory data = abi.decode(staticInput, (Data));

    if (block.timestamp > data.validUntil) revert IConditionalOrder.OrderNotValid(ORDER_EXPIRED);
    if (IERC20(data.fromToken).balanceOf(owner) < data.sellAmount) {
      revert IConditionalOrder.OrderNotValid(INSUFFICIENT_BALANCE);
    }

    if (data.sequencerUptimeFeed != address(0)) {
      _checkSequencer(data.sequencerUptimeFeed, data.sequencerGracePeriod);
    }

    if (
      AggregatorInterface(data.fromOracle).latestAnswer() <= 0 || AggregatorInterface(data.toOracle).latestAnswer() <= 0
    ) {
      revert IConditionalOrder.PollTryNextBlock(INVALID_ORACLE_PRICE);
    }

    uint256 buyAmount = OracleMath.getMinOut(
      data.fromToken, data.toToken, data.fromOracle, data.toOracle, data.sellAmount, data.slippage
    );
    if (buyAmount == 0) revert IConditionalOrder.OrderNotValid(ZERO_BUY_AMOUNT);

    return GPv2Order.Data({
      sellToken: IERC20(data.fromToken),
      buyToken: IERC20(data.toToken),
      receiver: data.receiver,
      sellAmount: data.sellAmount,
      buyAmount: buyAmount,
      validTo: data.validUntil,
      appData: data.appData,
      feeAmount: 0,
      kind: GPv2Order.KIND_SELL,
      partiallyFillable: false,
      sellTokenBalance: GPv2Order.BALANCE_ERC20,
      buyTokenBalance: GPv2Order.BALANCE_ERC20
    });
  }

  function _checkSequencer(address feed, uint32 gracePeriod) internal view {
    (, int256 answer, uint256 startedAt,,) = AggregatorInterface(feed).latestRoundData();
    if (answer != 0) revert IConditionalOrder.PollTryNextBlock(SEQUENCER_DOWN);
    if (startedAt == 0 || startedAt > block.timestamp) {
      revert IConditionalOrder.PollTryNextBlock(INVALID_SEQUENCER_TIMESTAMP);
    }
    if (block.timestamp - startedAt <= gracePeriod) {
      revert IConditionalOrder.PollTryAtEpoch(startedAt + gracePeriod + 1, SEQUENCER_GRACE_PERIOD_NOT_OVER);
    }
  }
}
