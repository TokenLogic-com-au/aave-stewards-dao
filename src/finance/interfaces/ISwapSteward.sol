// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IComposableCow} from "src/finance/interfaces/IComposableCow.sol";

interface ISwapSteward {
  /// @dev Open swap owned by a SwapEscrow clone
  struct Swap {
    address fromToken;
    bytes32 orderHash;
  }

  /// @dev Slippage is too high
  error InvalidSlippage();

  /// @dev Provided address cannot be the zero-address
  error InvalidZeroAddress();

  /// @dev Amount cannot be zero
  error InvalidZeroAmount();

  /// @dev Amount requested is greater than token budget
  error InsufficientBudget();

  /// @dev Oracle has not been set for the token
  error OracleNotSet();

  /// @dev Oracle does not have correct number of decimals
  error PriceFeedIncompatibleDecimals();

  /// @dev Oracle is returning unexpected value
  error PriceFeedInvalidAnswer();

  /// @dev Start time of the TWAP is in the past
  error StartTimeInPast();

  /// @dev There is no open swap owned by the escrow
  error SwapNotFound();

  /// @dev Token pair has not been set for swapping
  error UnrecognizedTokenSwap();

  /// @notice Emitted when a token pair is allowed or disallowed for swapping
  /// @param fromToken The address of the token to swap from
  /// @param toToken The address of the token to swap to
  /// @param allowed Whether token pair is allowed or disallowed
  event SetSwappablePair(address indexed fromToken, address indexed toToken, bool allowed);

  /// @notice Emitted when an oracle address is set for a given token
  /// @param token The address of the token
  /// @param oracle The address of the token oracle
  event SetTokenOracle(address indexed token, address indexed oracle);

  /// @notice Emitted when a token's budget is updated
  /// @param token The address of the token
  /// @param budget The budget set for the token
  event UpdatedTokenBudget(address indexed token, uint256 budget);

  /// @notice Emitted when an oracle market swap is requested
  /// @param escrow The SwapEscrow clone that owns the swap
  /// @param orderHash Hash of the conditional order on ComposableCoW
  /// @param fromToken The token to swap from
  /// @param toToken The token to swap to
  /// @param fromOracle The oracle used to price fromToken
  /// @param toOracle The oracle used to price toToken
  /// @param amount The amount of fromToken to swap
  /// @param slippage The maximum allowed slippage for the swap
  event SwapRequested(
    address indexed escrow,
    bytes32 orderHash,
    address indexed fromToken,
    address indexed toToken,
    address fromOracle,
    address toOracle,
    uint256 amount,
    uint256 slippage
  );

  /// @notice Emitted when a TWAP swap is requested
  /// @param escrow The SwapEscrow clone that owns the swap
  /// @param orderHash Hash of the conditional order on ComposableCoW
  /// @param fromToken The token to swap from
  /// @param toToken The token to swap to
  /// @param totalAmount The total amount of fromToken to swap
  event TWAPSwapRequested(
    address indexed escrow, bytes32 orderHash, address indexed fromToken, address indexed toToken, uint256 totalAmount
  );

  /// @notice Emitted when an open swap is canceled
  /// @param escrow The SwapEscrow clone that owned the swap
  /// @param orderHash Hash of the conditional order on ComposableCoW
  /// @param fromToken The token that was being swapped from
  /// @param amount The amount of fromToken returned to the Collector
  event SwapCanceled(address indexed escrow, bytes32 orderHash, address indexed fromToken, uint256 amount);

  /// @notice Returns address of Aave V3 Collector, the receiver of every swap and refund
  function COLLECTOR() external view returns (address);

  /// @notice Returns the maximum allowed slippage for swaps (in BPS)
  function MAX_SLIPPAGE() external view returns (uint256);

  /// @notice Returns the handler of oracle market orders
  function MARKET_ORDER_HANDLER() external view returns (address);

  /// @notice Returns the handler of TWAP orders
  function TWAP_HANDLER() external view returns (address);

  /// @notice Returns the ComposableCoW contract
  function COMPOSABLE_COW() external view returns (IComposableCow);

  /// @notice Returns the SwapEscrow implementation that every swap clones
  function SWAP_ESCROW_IMPLEMENTATION() external view returns (address);

  /// @notice Returns the Chainlink L2 sequencer uptime feed, zero on chains without one
  function SEQUENCER_UPTIME_FEED() external view returns (address);

  /// @notice Returns the lifetime in seconds of an oracle market order, after which it cannot be settled
  function ORDER_LIFETIME() external view returns (uint32);

  /// @notice Returns the seconds the sequencer must be up before oracle market orders are generated
  function SEQUENCER_GRACE_PERIOD() external view returns (uint32);

  /// @notice Returns the appData pinned on every order
  function APP_DATA() external view returns (bytes32);

  /// @notice Returns whether the path from fromToken to toToken is approved for swapping
  /// @param fromToken Address of the token to swap from
  /// @param toToken Address of the token to swap to
  function swapApprovedPair(address fromToken, address toToken) external view returns (bool);

  /// @notice Returns address of the Oracle to use for token swaps
  /// @param token Address of the token to swap
  function priceOracle(address token) external view returns (address);

  /// @notice Returns the budget remaining for a given token
  /// @param token The address of the token to query the budget for
  function tokenBudget(address token) external view returns (uint256);

  /// @notice Returns the open swap owned by a SwapEscrow clone, or zero values if there is none
  /// @param escrow Address of the SwapEscrow clone
  function swaps(address escrow) external view returns (address fromToken, bytes32 orderHash);

  /// @notice Swaps a specified amount of a sell token for a buy token at the oracle price, minus slippage
  /// @dev Deploys a SwapEscrow clone that owns the order. Guardian swaps consume the token budget
  /// @param fromToken The address of the token to sell
  /// @param toToken The address of the token to buy
  /// @param amount The amount of the sell token to swap. `type(uint256).max` resolves to the Collector balance of
  ///        the sell token when called by the owner, and to the remaining token budget when called by the guardian
  /// @param slippage The slippage allowed in the swap (in BPS)
  function swap(address fromToken, address toToken, uint256 amount, uint256 slippage) external;

  /// @notice Swaps a specified total amount of a sell token for a buy token in equal parts over time
  /// @dev Deploys a SwapEscrow clone that owns the order and holds `partSellAmount * numParts` of fromToken.
  ///      Guardian swaps consume the token budget. `minPartLimit` is a fixed limit, it is not checked against the
  ///      oracles. Reverts with `StartTimeInPast` if `startTime` is non-zero and before the current block timestamp.
  ///      Reverts with `IConditionalOrder.OrderNotValid` unless the resolved parameters satisfy the TWAP handler
  ///      rules: `minPartLimit` > 0, start time < type(uint32).max, 1 < `numParts` <= type(uint32).max,
  ///      0 < `partDuration` <= 365 days and `span` <= `partDuration`
  /// @param fromToken Address of the token to swap from
  /// @param toToken Address of the token to swap to
  /// @param partSellAmount The amount of fromToken to sell in each part
  /// @param minPartLimit The minimum amount of toToken to receive per part
  /// @param startTime Start time of the TWAP, 0 to start at the current block timestamp
  /// @param numParts Number of parts
  /// @param partDuration Duration of each part, in seconds
  /// @param span Window of each part during which it can be filled, 0 for the whole part duration
  function twapSwap(
    address fromToken,
    address toToken,
    uint256 partSellAmount,
    uint256 minPartLimit,
    uint256 startTime,
    uint256 numParts,
    uint256 partDuration,
    uint256 span
  ) external;

  /// @notice Cancels an open swap and returns its unfilled fromToken to the Collector
  /// @dev Removes the order from ComposableCoW, zeroes the relayer allowance of the clone and sends the
  ///      full fromToken balance of the clone to the Collector. Also used to clean up a filled swap
  /// @param escrow The SwapEscrow clone that owns the swap
  function cancelSwap(address escrow) external;

  /// @notice Increases the budget of a token
  /// @param token The address of the token
  /// @param budget The amount to add to the budget
  function increaseTokenBudget(address token, uint256 budget) external;

  /// @notice Decreases the budget of a token
  /// @param token The address of the token
  /// @param budget The amount to remove from the budget
  function decreaseTokenBudget(address token, uint256 budget) external;

  /// @notice Allows or disallows a token pair for swapping
  /// @param fromToken The address of the token to swap from
  /// @param toToken The address of the token to swap to
  /// @param allowed Whether the pair is allowed
  function setSwappablePair(address fromToken, address toToken, bool allowed) external;

  /// @notice Sets the oracle of a token
  /// @dev The oracle must have 8 decimals and return a positive `latestAnswer`
  /// @param token The address of the token
  /// @param oracle The address of the oracle
  function setTokenOracle(address token, address oracle) external;

  /// @notice Transfers the full balance of a token held by this contract to the Collector
  /// @param token The address of the token to rescue
  function rescueToken(address token) external;

  /// @notice Transfers an amount of a token held by this contract to the Collector
  /// @param token The address of the token to rescue
  /// @param amount The amount to rescue
  function rescueToken(address token, uint256 amount) external;

  /// @notice Returns the expected amount of toToken for an amount of fromToken at the oracle prices, before slippage
  /// @param amount The amount of fromToken
  /// @param fromToken Address of the token to swap from
  /// @param toToken Address of the token to swap to
  function getExpectedOut(uint256 amount, address fromToken, address toToken) external view returns (uint256);
}
