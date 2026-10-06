// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface ISwapSteward {
  /// @dev Static input of the upstream TWAP handler
  struct TWAPData {
    IERC20 sellToken;
    IERC20 buyToken;
    address receiver;
    uint256 partSellAmount; // amount of sellToken to sell in each part
    uint256 minPartLimit; // minimum amount of tokens to receive per part
    uint256 t0;
    uint256 n;
    uint256 t;
    uint256 span;
    bytes32 appData;
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

  /// @dev A swap of fromToken is already pending; only one pending swap per fromToken is allowed
  error SwapAlreadyPending();

  /// @dev There is no pending swap of fromToken
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
  /// @param orderHash Hash of the conditional order on ComposableCoW
  /// @param fromToken The token to swap from
  /// @param toToken The token to swap to
  /// @param fromOracle The oracle used to price fromToken
  /// @param toOracle The oracle used to price toToken
  /// @param amount The amount of fromToken to swap
  /// @param slippage The maximum allowed slippage for the swap
  event SwapRequested(
    bytes32 orderHash,
    address indexed fromToken,
    address indexed toToken,
    address fromOracle,
    address toOracle,
    uint256 amount,
    uint256 slippage
  );

  /// @notice Emitted when a limit swap is requested
  /// @param orderHash Hash of the conditional order on ComposableCoW
  /// @param fromToken The token to swap from
  /// @param toToken The token to swap to
  /// @param amount The amount of fromToken to swap
  /// @param minAmountOut The minimum amount of toToken expected to receive
  event LimitSwapRequested(
    bytes32 orderHash, address indexed fromToken, address indexed toToken, uint256 amount, uint256 minAmountOut
  );

  /// @notice Emitted when a TWAP swap is requested
  /// @param orderHash Hash of the conditional order on ComposableCoW
  /// @param fromToken The token to swap from
  /// @param toToken The token to swap to
  /// @param totalAmount The total amount of fromToken to swap
  event TWAPSwapRequested(bytes32 orderHash, address indexed fromToken, address indexed toToken, uint256 totalAmount);

  /// @notice Emitted when a pending swap is canceled
  /// @param orderHash Hash of the conditional order on ComposableCoW
  /// @param fromToken The token that was being swapped from
  /// @param amount The amount of fromToken returned to the Collector
  event SwapCanceled(bytes32 indexed orderHash, address indexed fromToken, uint256 amount);

  /// @notice Returns address of Aave V3 Collector, the receiver of every swap and refund
  function COLLECTOR() external view returns (address);

  /// @notice Returns the maximum allowed slippage for swaps (in BPS)
  function MAX_SLIPPAGE() external view returns (uint256);

  /// @notice Returns the handler of oracle market orders
  function MARKET_ORDER_HANDLER() external view returns (address);

  /// @notice Returns the handler of limit orders
  function LIMIT_ORDER_HANDLER() external view returns (address);

  /// @notice Returns the handler of TWAP orders
  function TWAP_HANDLER() external view returns (address);

  /// @notice Returns the GPv2VaultRelayer that pulls the sold tokens
  function VAULT_RELAYER() external view returns (address);

  /// @notice Returns the appData pinned on every order
  function APP_DATA() external view returns (bytes32);

  /// @notice Returns whether token is approved to be swapped from/to
  /// @param fromToken Address of the token to swap from
  /// @param toToken Address of the token to swap to
  function swapApprovedToken(address fromToken, address toToken) external view returns (bool);

  /// @notice Returns address of the Oracle to use for token swaps
  /// @param token Address of the token to swap
  function priceOracle(address token) external view returns (address);

  /// @notice Returns the budget remaining for a given token
  /// @param token The address of the token to query the budget for
  function tokenBudget(address token) external view returns (uint256);

  /// @notice Returns the hash of the pending conditional order of fromToken, or zero if there is none
  /// @param fromToken Address of the token being swapped from
  function pendingOrder(address fromToken) external view returns (bytes32);

  /// @notice Swaps a specified amount of a sell token for a buy token at the oracle price, minus slippage
  /// @dev Reverts if a swap of fromToken is already pending. Guardian swaps consume the token budget
  /// @param fromToken The address of the token to sell
  /// @param toToken The address of the token to buy
  /// @param amount The amount of the sell token to swap, type(uint256).max for the maximum allowed
  /// @param slippage The slippage allowed in the swap (in BPS)
  /// @return orderHash Hash of the conditional order on ComposableCoW
  function swap(address fromToken, address toToken, uint256 amount, uint256 slippage)
    external
    returns (bytes32 orderHash);

  /// @notice Swaps a specified amount of a sell token for a buy token with a limit price
  /// @dev Reverts if a swap of fromToken is already pending. Guardian swaps consume the token budget
  /// @param fromToken Address of the token to swap from
  /// @param toToken Address of the token to swap to
  /// @param amount The amount of fromToken to swap, type(uint256).max for the maximum allowed
  /// @param amountOut The limit price of the toToken (minimum amount to receive)
  /// @return orderHash Hash of the conditional order on ComposableCoW
  function limitSwap(address fromToken, address toToken, uint256 amount, uint256 amountOut)
    external
    returns (bytes32 orderHash);

  /// @notice Swaps a specified total amount of a sell token for a buy token in equal parts over time
  /// @dev Reverts if a swap of fromToken is already pending. Guardian swaps consume the token budget
  /// @param fromToken Address of the token to swap from
  /// @param toToken Address of the token to swap to
  /// @param partSellAmount The amount of fromToken to sell in each part
  /// @param minPartLimit The minimum amount of toToken to receive per part
  /// @param startTime Start time of the TWAP, 0 to start when the order is created
  /// @param numParts Number of parts
  /// @param partDuration Duration of each part, in seconds
  /// @param span Window of each part during which it can be filled, 0 for the whole part duration
  /// @return orderHash Hash of the conditional order on ComposableCoW
  function twapSwap(
    address fromToken,
    address toToken,
    uint256 partSellAmount,
    uint256 minPartLimit,
    uint256 startTime,
    uint256 numParts,
    uint256 partDuration,
    uint256 span
  ) external returns (bytes32 orderHash);

  /// @notice Cancels the pending swap of fromToken and returns its unfilled fromToken to the Collector
  /// @dev Removes the order from ComposableCoW, zeroes the relayer allowance and sends the full
  ///      fromToken balance of this contract to the Collector
  /// @param fromToken The token whose pending swap is canceled
  function cancelSwap(address fromToken) external;

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
