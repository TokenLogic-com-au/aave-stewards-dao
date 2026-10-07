// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev Subset of the Chainlink L2 sequencer uptime feed (AggregatorV3Interface)
interface ISequencerUptimeFeed {
  /// @return roundId Round id
  /// @return answer 0 when the sequencer is up, 1 when it is down
  /// @return startedAt Timestamp at which the sequencer last changed status
  /// @return updatedAt Timestamp of the last update
  /// @return answeredInRound Round id in which the answer was computed
  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
