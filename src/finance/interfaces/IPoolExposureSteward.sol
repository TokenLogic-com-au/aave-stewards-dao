// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICollector} from "aave-helpers/src/CollectorUtils.sol";

interface IPoolExposureSteward {
  /// @dev Provided address cannot be the zero-address
  error InvalidZeroAddress();

  /// @dev Provided arrays do not have the same length
  error MismatchingArrayLength();

  /// @dev Aave Pool must have been previously approved
  error UnrecognizedPool();

  /// @dev Aave V4 TokenizationSpoke must have been previously approved
  error UnrecognizedTokenizationSpoke();

  /// @dev Both Aave V4 TokenizationSpokes must tokenize the same underlying asset
  error MismatchingTokenizationSpokeAssets();

  /// @dev Origin and destination Aave V4 TokenizationSpokes must be different
  error SameTokenizationSpoke();

  /// @dev Aave V4 TokenizationSpoke is already approved
  error TokenizationSpokeAlreadyApproved();

  /// @dev Aave V4 TokenizationSpoke is not listed on its Hub for the underlying it reports
  error InvalidTokenizationSpoke();

  /// @notice Emitted when a new V2 Pool gets listed
  /// @param pool The address of the new pool
  event ApprovedV2Pool(address indexed pool);

  /// @notice Emitted when a new V3 Pool gets listed
  /// @param pool The address of the new pool
  event ApprovedV3Pool(address indexed pool);

  /// @notice Emitted when a new V4 TokenizationSpoke gets listed
  /// @param tokenizationSpoke The address of the new TokenizationSpoke
  event ApprovedTokenizationSpoke(address indexed tokenizationSpoke);

  /// @notice Emitted when a V2 Pool gets removed
  /// @param pool The address of the revoked pool
  event RevokedV2Pool(address indexed pool);

  /// @notice Emitted when a V3 Pool gets removed
  /// @param pool The address of the revoked pool
  event RevokedV3Pool(address indexed pool);

  /// @notice Emitted when a V4 TokenizationSpoke gets removed
  /// @param tokenizationSpoke The address of the revoked TokenizationSpoke
  event RevokedTokenizationSpoke(address indexed tokenizationSpoke);

  /// @notice Returns instance of Aave V3 Collector
  function COLLECTOR() external view returns (ICollector);

  /// @notice Returns whether pool is approved to be used
  /// @param poolV2 Address of the Aave V2 Pool
  function approvedV2Pools(address poolV2) external view returns (bool);

  /// @notice Returns whether pool is approved to be used
  /// @param poolV3 Address of the Aave V3 Pool
  function approvedV3Pools(address poolV3) external view returns (bool);

  /// @notice Returns whether a TokenizationSpoke is approved to be used
  /// @param tokenizationSpoke The address of the Aave V4 TokenizationSpoke
  /// @return True if the TokenizationSpoke is approved
  function approvedTokenizationSpokes(address tokenizationSpoke) external view returns (bool);

  /// @notice Deposits a specified amount of a reserve token into Aave V3
  /// @param pool The address of the V3 Pool to deposit into
  /// @param reserve The address of the reserve token
  /// @param amount The amount of the reserve token to deposit
  function depositV3(address pool, address reserve, uint256 amount) external;

  /// @notice Deposits a specified amount of the Collector's underlying into an Aave V4 TokenizationSpoke
  /// @dev The underlying is derived from the TokenizationSpoke
  /// @param tokenizationSpoke The address of the Aave V4 TokenizationSpoke to deposit into
  /// @param amount The amount of underlying to deposit, type(uint256).max for the full Collector balance
  /// @return The amount of TokenizationSpoke shares minted to the Collector
  function depositV4(address tokenizationSpoke, uint256 amount) external returns (uint256);

  /// @notice Withdraws a specified amount of a reserve token from Aave V2
  /// @param pool The address of the V2 Pool to withdraw from
  /// @param reserve The address of the reserve token to withdraw
  /// @param amount The amount of the reserve token to withdraw
  function withdrawV2(address pool, address reserve, uint256 amount) external;

  /// @notice Withdraws a specified amount of a reserve token from Aave V3
  /// @param V3Pool The address of the V3 pool to withdraw from
  /// @param underlying The address of the reserve token to withdraw
  /// @param amount The amount of the reserve token to withdraw
  function withdrawV3(address V3Pool, address underlying, uint256 amount) external;

  /// @notice Withdraws a specified amount of underlying from an Aave V4 TokenizationSpoke back to the Collector
  /// @dev If amount is type(uint256).max, the withdrawal is capped by the Hub's available liquidity
  /// @dev This can withdraw less than the Collector's full position without reverting, so use the returned amount
  /// @param tokenizationSpoke The address of the Aave V4 TokenizationSpoke to withdraw from
  /// @param amount The amount of underlying to withdraw, type(uint256).max for the max withdrawable by the Collector
  /// @return The actual amount of underlying withdrawn
  function withdrawV4(address tokenizationSpoke, uint256 amount) external returns (uint256);

  /// @notice Migrates a specified amount of a reserve token from Aave V2 to Aave V3
  /// @param v2Pool The address of the origin V2 Pool
  /// @param v3Pool The address of the destination V3 Pool
  /// @param underlying The address of the reserve token
  /// @param amount The amount of the reserve token to migrate
  function migrateV2toV3(address v2Pool, address v3Pool, address underlying, uint256 amount) external;

  /// @notice Migrates a specified amount of a reserve token from an Aave V3 instance to another
  /// @param fromPool The address of the origin V3 Pool
  /// @param toPool The address of the destination V3 Pool
  /// @param underlying The address of the reserve token
  /// @param amount The amount of the reserve token to migrate
  function migrateBetweenV3(address fromPool, address toPool, address underlying, uint256 amount) external;

  /// @notice Migrates a specified amount of underlying from Aave V2 to an Aave V4 TokenizationSpoke
  /// @dev The underlying is derived from the TokenizationSpoke
  /// @param v2Pool The address of the origin V2 Pool
  /// @param tokenizationSpoke The address of the destination Aave V4 TokenizationSpoke
  /// @param amount The amount of underlying to migrate, `type(uint256).max` for the Collector's full V2 aToken balance
  /// @return The amount of TokenizationSpoke shares minted to the Collector
  function migrateV2toV4(address v2Pool, address tokenizationSpoke, uint256 amount) external returns (uint256);

  /// @notice Migrates a specified amount of underlying from Aave V3 to an Aave V4 TokenizationSpoke
  /// @dev The underlying is derived from the TokenizationSpoke
  /// @param v3Pool The address of the origin V3 Pool
  /// @param tokenizationSpoke The address of the destination Aave V4 TokenizationSpoke
  /// @param amount The amount of underlying to migrate, `type(uint256).max` for the Collector's full V3 aToken balance
  /// @return The amount of TokenizationSpoke shares minted to the Collector
  function migrateV3toV4(address v3Pool, address tokenizationSpoke, uint256 amount) external returns (uint256);

  /// @notice Migrates a specified amount of underlying between two Aave V4 TokenizationSpokes of the same asset
  /// @dev If amount is type(uint256).max, the withdrawal is capped by the origin Hub's available liquidity
  /// @param fromTokenizationSpoke The address of the origin Aave V4 TokenizationSpoke
  /// @param toTokenizationSpoke The address of the destination Aave V4 TokenizationSpoke
  /// @param amount The amount of underlying to migrate, type(uint256).max for the max withdrawable by the Collector
  /// @return The amount of destination TokenizationSpoke shares minted to the Collector
  function migrateBetweenV4(address fromTokenizationSpoke, address toTokenizationSpoke, uint256 amount)
    external
    returns (uint256);

  /// @notice Approves the permission to use a new pool
  /// @param pool Address of the new Pool
  /// @param version3 True if new pool is a V3 instance
  function approvePool(address pool, bool version3) external;

  /// @notice Revokes the permission to use a pool
  /// @param pool Address of the Pool to remove
  /// @param version3 True if the pool is a V3 instance
  function revokePool(address pool, bool version3) external;

  /// @notice Approves the permission to use a new Aave V4 TokenizationSpoke
  /// @param tokenizationSpoke The address of the new Aave V4 TokenizationSpoke
  function approveTokenizationSpoke(address tokenizationSpoke) external;

  /// @notice Revokes the permission to use an Aave V4 TokenizationSpoke
  /// @param tokenizationSpoke The address of the Aave V4 TokenizationSpoke to remove
  function revokeTokenizationSpoke(address tokenizationSpoke) external;

  /// @notice Rescues the specified token back to the Collector
  /// @param token The address of the ERC20 token to rescue
  function rescueToken(address token) external;

  /// @notice Rescues ETH from the contract back to the Collector
  function rescueEth() external;
}
