// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ComposableCoW} from "composable-cow/ComposableCoW.sol";
import {TWAP, NOT_WITHIN_SPAN} from "composable-cow/types/twap/TWAP.sol";
import {AFTER_TWAP_FINISH} from "composable-cow/types/twap/libraries/TWAPOrderMathLib.sol";
import {GPv2Settlement} from "cowprotocol/contracts/GPv2Settlement.sol";
import {GPv2AllowListAuthentication} from "cowprotocol/contracts/GPv2AllowListAuthentication.sol";
import {IVault} from "cowprotocol/contracts/interfaces/IVault.sol";
import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";
import {IComposableCow} from "src/finance/interfaces/IComposableCow.sol";
import {MockAggregator} from "tests/finance/swap/OracleMocks.sol";
import {SwapStewardTestUtils} from "tests/finance/swap/SwapStewardTestUtils.sol";

/**
 * @dev Stands in for the aave-v3-origin Collector, which cannot be compiled in this repository: its
 * AccessControlUpgradeable base imports the OpenZeppelin package of the composable-cow remapping, an older release
 * that lacks the `AccessControlUnauthorizedAccount` error. Reproduces the one surface SwapSteward uses,
 * `transfer` gated by FUNDS_ADMIN_ROLE that reverts with `ICollector.OnlyFundsAdmin` like the real Collector, and the
 * admin that grants that role.
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
 * @dev Non-fork fixture of the SwapSteward suites. Deploys the pinned ComposableCoW, TWAP handler, GPv2Settlement and
 * GPv2AllowListAuthentication from lib/composable-cow, a MockCollector, and mock tokens and oracles. The swap token is
 * a 6-decimal USDC, the buy token a 18-decimal WETH.
 * command: forge test -vvv --match-path 'tests/finance/swap/Swap{Steward,Escrow}.*.t.sol'
 */
abstract contract SwapStewardTestBase is SwapStewardTestUtils {
  uint256 internal constant ORACLE_MOVE_BPS = 100;
  uint256 internal constant TWAP_SPAN = 30 minutes;
  uint256 internal constant START_TIME = 1_800_000_000;
  uint8 internal constant FROM_DECIMALS = 6;
  uint8 internal constant TO_DECIMALS = 18;
  uint8 internal constant OTHER_DECIMALS = 18;
  int256 internal constant FROM_PRICE = 1e8;
  int256 internal constant TO_PRICE = 2000e8;
  int256 internal constant OTHER_PRICE = 10e8;
  uint256 internal constant COLLECTOR_BALANCE = 200e6;
  /// @dev Wei of WETH per unit of USDC at the oracle prices: 1e8 * 1e18 / (2000e8 * 1e6)
  uint256 internal constant OUT_PER_FROM_UNIT = 5e8;
  /// @dev `swapAmount` of USDC at the oracle prices: 10 USD / 2000 USD per WETH = 0.005 WETH
  uint256 internal constant EXPECTED_OUT = 5e15;
  /// @dev `EXPECTED_OUT` less the 50 bps slippage of `SWAP_SLIPPAGE`: 0.005 WETH * 99.5%
  uint256 internal constant EXPECTED_BUY_AMOUNT = 4_975e12;

  address internal alice = makeAddr("alice");

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

    GPv2AllowListAuthentication authenticator = new GPv2AllowListAuthentication();
    authenticator.initializeManager(makeAddr("authenticatorManager"));
    settlement = new GPv2Settlement(authenticator, IVault(makeAddr("balancerVault")));
    vaultRelayer = address(settlement.vaultRelayer());

    ComposableCoW cow = new ComposableCoW(address(settlement));
    composableCow = IComposableCow(address(cow));
    twapHandler = address(new TWAP(cow));

    collector = address(new MockCollector(executor));
    deal(fromToken, collector, COLLECTOR_BALANCE);

    _deploySteward();
    _allowSolver();
  }

  function _approvePairsWithOtherToken() internal {
    vm.startPrank(executor);
    steward.setSwappablePair(fromToken, otherToken, true);
    steward.setSwappablePair(otherToken, fromToken, true);
    vm.stopPrank();
  }
}
