// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PercentageMath} from "aave-v3-origin/contracts/protocol/libraries/math/PercentageMath.sol";
import {AggregatorInterface} from "aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol";

/**
 * @title OracleMath
 * @author halaprix
 * @notice Computes the expected output amount of a swap from two 8-decimal Chainlink-style oracle prices
 */
library OracleMath {
  /// @notice Thrown when an oracle reports a price lower than or equal to zero
  /// @param oracle Address of the oracle that reported the price
  error InvalidPrice(address oracle);

  /**
   * @notice Returns the amount of toToken equivalent to `amount` of fromToken at the oracle prices, rounded down
   * @dev Both oracles must quote in the same currency and have the same decimals (8, enforced by the steward).
   *      Prices are read with `latestAnswer`, no staleness check is performed.
   * @param fromToken Token being sold
   * @param toToken Token being bought
   * @param fromOracle Oracle pricing fromToken
   * @param toOracle Oracle pricing toToken
   * @param amount Amount of fromToken, in fromToken decimals
   * @return Expected amount of toToken, in toToken decimals
   */
  function getExpectedOut(address fromToken, address toToken, address fromOracle, address toOracle, uint256 amount)
    internal
    view
    returns (uint256)
  {
    uint256 pFrom = _price(fromOracle);
    uint256 pTo = _price(toOracle);
    uint8 fromDecimals = IERC20Metadata(fromToken).decimals();
    uint8 toDecimals = IERC20Metadata(toToken).decimals();

    return Math.mulDiv(amount, pFrom * 10 ** toDecimals, pTo * 10 ** fromDecimals);
  }

  /**
   * @notice Returns the minimum amount of toToken accepted for `amount` of fromToken, the expected out reduced by slippage, rounded down
   * @dev Reverts on underflow if `slippage` exceeds `PercentageMath.PERCENTAGE_FACTOR`, callers must cap it.
   * @param fromToken Token being sold
   * @param toToken Token being bought
   * @param fromOracle Oracle pricing fromToken
   * @param toOracle Oracle pricing toToken
   * @param amount Amount of fromToken, in fromToken decimals
   * @param slippage Allowed slippage against the oracle price, where 100_00 is equal to 100%
   * @return Minimum amount of toToken, in toToken decimals
   */
  function getMinOut(
    address fromToken,
    address toToken,
    address fromOracle,
    address toOracle,
    uint256 amount,
    uint256 slippage
  ) internal view returns (uint256) {
    return PercentageMath.percentMulFloor(
      getExpectedOut(fromToken, toToken, fromOracle, toOracle, amount), PercentageMath.PERCENTAGE_FACTOR - slippage
    );
  }

  function _price(address oracle) private view returns (uint256) {
    int256 answer = AggregatorInterface(oracle).latestAnswer();
    if (answer <= 0) revert InvalidPrice(oracle);

    return SafeCast.toUint256(answer);
  }
}
