// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {BaseConditionalOrder} from "src/finance/BaseConditionalOrder.sol";
import {GPv2Order} from "src/finance/libraries/GPv2Order.sol";

/**
 * @title OracleMarketOrder
 * @author halaprix
 * @notice Conditional order handler that prices a market swap from Chainlink oracles at execution time
 */
contract OracleMarketOrder is BaseConditionalOrder {
  /// @notice Static input of the conditional order
  /// @param fromToken Token being sold
  /// @param toToken Token being bought
  /// @param fromOracle Oracle pricing fromToken
  /// @param toOracle Oracle pricing toToken
  /// @param receiver Receiver of the bought token, the Collector
  /// @param sellAmount Amount of fromToken to sell
  /// @param slippage Allowed slippage against the oracle price, where 100_00 is equal to 100%
  /// @param appData appData pinned on the order
  /// @param validityBucket Size in seconds of the time bucket that `validTo` is rounded up to
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
    uint32 validityBucket;
    address sequencerUptimeFeed;
    uint32 sequencerGracePeriod;
  }

  /// @inheritdoc BaseConditionalOrder
  function getTradeableOrder(address, address, bytes32, bytes calldata, bytes calldata)
    public
    view
    override
    returns (GPv2Order.Data memory)
  {}
}
