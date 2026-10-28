// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";
import {AggregatorInterface} from "aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol";
import {MockAggregator} from "tests/finance/swap/OracleMocks.sol";
import {IComposableCow} from "src/finance/interfaces/IComposableCow.sol";
import {IConditionalOrder} from "src/finance/interfaces/IConditionalOrder.sol";
import {SwapStewardTestUtils} from "tests/finance/swap/SwapStewardTestUtils.sol";

/**
 * @dev Stands in for the aave-v3-origin Collector. Reproduces the one surface SwapSteward uses, `transfer` gated by
 * FUNDS_ADMIN_ROLE that reverts with `ICollector.OnlyFundsAdmin` like the real Collector, and the admin that grants
 * that role.
 */
contract MockCollector is AccessControl {
  using SafeERC20 for IERC20;

  bytes32 public constant FUNDS_ADMIN_ROLE = "FUNDS_ADMIN";

  constructor(address admin) {
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(FUNDS_ADMIN_ROLE, admin);
  }

  function transfer(IERC20 token, address recipient, uint256 amount) external {
    if (!hasRole(FUNDS_ADMIN_ROLE, msg.sender)) revert ICollector.OnlyFundsAdmin();
    token.safeTransfer(recipient, amount);
  }
}

/**
 * @dev Stands in for ComposableCoW. Reproduces the order registry SwapEscrow and SwapSteward use: `create`, `remove`,
 * `hash` and `singleOrders`, with the same hash and event as the deployed contract. Signature verification and order
 * generation are not mocked; tests that need them run on the mainnet fork fixture.
 */
contract MockComposableCow {
  mapping(address owner => mapping(bytes32 orderHash => bool)) public singleOrders;

  function create(IConditionalOrder.ConditionalOrderParams calldata params, bool dispatch) external {
    singleOrders[msg.sender][hash(params)] = true;
    if (dispatch) emit IComposableCow.ConditionalOrderCreated(msg.sender, params);
  }

  function remove(bytes32 orderHash) external {
    singleOrders[msg.sender][orderHash] = false;
  }

  function hash(IConditionalOrder.ConditionalOrderParams memory params) public pure returns (bytes32) {
    return keccak256(abi.encode(params));
  }
}

/**
 * @dev Unit fixture of the SwapSteward suites. No fork: ComposableCoW is a MockComposableCow, the TWAP handler and
 * vault relayer are placeholder addresses, and tokens, oracles and the Collector are mocks. The swap token is a
 * 6-decimal USDC, the buy token a 18-decimal WETH. Subclasses override `_setUpCow` to use the deployed CoW contracts.
 * command: forge test -vvv --match-path 'tests/finance/swap/Swap{Steward,Escrow}.*.t.sol' --no-match-path '*Fork*'
 */
abstract contract SwapStewardTestBase is SwapStewardTestUtils {
  uint256 internal constant ORACLE_MOVE_BPS = 100;
  uint256 internal constant START_TIME = 1_800_000_000;
  uint8 internal constant FROM_DECIMALS = 6;
  uint8 internal constant TO_DECIMALS = 18;
  uint8 internal constant OTHER_DECIMALS = 18;
  int256 internal constant FROM_PRICE = 1e8;
  int256 internal constant TO_PRICE = 2000e8;
  int256 internal constant OTHER_PRICE = 10e8;
  uint256 internal constant COLLECTOR_BALANCE = 200e6;
  /// @dev `swapAmount` of USDC at the oracle prices: 10 USD / 2000 USD per WETH = 0.005 WETH
  uint256 internal constant EXPECTED_OUT = 5e15;
  /// @dev `EXPECTED_OUT` less the 50 bps slippage of `SWAP_SLIPPAGE`: 0.005 WETH * 99.5%
  uint256 internal constant EXPECTED_BUY_AMOUNT = 4_975e12;
  uint256 internal constant TWAP_MAX_PART_DURATION = 365 days;

  address internal alice = makeAddr("alice");
  address internal otherToken;
  address internal otherOracle;

  function setUp() public virtual {
    vm.warp(START_TIME);

    executor = makeAddr("executor");
    swapAmount = 10e6;
    guardianBudget = 50e6;
    twapPartAmount = 5e6;
    twapMinPartLimit = 1e15;

    fromToken = address(deployMockERC20("USD Coin", "USDC", FROM_DECIMALS));
    toToken = address(deployMockERC20("Wrapped Ether", "WETH", TO_DECIMALS));
    otherToken = address(deployMockERC20("Chainlink", "LINK", OTHER_DECIMALS));
    fromOracle = address(new MockAggregator(FROM_PRICE));
    toOracle = address(new MockAggregator(TO_PRICE));
    otherOracle = address(new MockAggregator(OTHER_PRICE));

    _setUpCow();

    collector = address(new MockCollector(executor));
    deal(fromToken, collector, COLLECTOR_BALANCE);

    _deploySteward();
  }

  function _setUpCow() internal virtual {
    composableCow = IComposableCow(address(new MockComposableCow()));
    twapHandler = makeAddr("twapHandler");
    vaultRelayer = makeAddr("vaultRelayer");
  }

  function _mockLatestAnswer(address oracle, int256 answer) internal {
    vm.mockCall(oracle, abi.encodeWithSelector(AggregatorInterface.latestAnswer.selector), abi.encode(answer));
  }

  function _approvePairsWithOtherToken() internal {
    vm.startPrank(executor);
    steward.setSwappablePair(fromToken, otherToken);
    steward.setSwappablePair(otherToken, fromToken);
    vm.stopPrank();
  }
}
