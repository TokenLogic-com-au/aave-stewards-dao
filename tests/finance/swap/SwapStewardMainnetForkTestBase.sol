// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {COMPOSABLE_COW, TWAP_HANDLER} from "scripts/DeploySwapSteward.s.sol";
import {IComposableCow} from "src/finance/interfaces/IComposableCow.sol";
import {IGPv2Settlement} from "src/finance/interfaces/IGPv2Settlement.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

/**
 * @dev SwapStewardTestBase on a pinned mainnet fork with the deployed ComposableCoW, TWAP handler and GPv2Settlement,
 * and the mock tokens, oracles and Collector of the unit fixture. For tests that need real CoW protocol logic:
 * EIP-1271 verification, order generation and settlement.
 * command: forge test -vvv --match-path 'tests/finance/swap/*.Fork.t.sol'
 */
abstract contract SwapStewardMainnetForkTestBase is SwapStewardTestBase {
  function setUp() public virtual override {
    vm.createSelectFork(vm.rpcUrl("mainnet"), MAINNET_FORK_BLOCK);
    super.setUp();
    _allowSolver();
  }

  function _setUpCow() internal override {
    settlement = IGPv2Settlement(GPV2_SETTLEMENT);
    vaultRelayer = settlement.vaultRelayer();
    composableCow = IComposableCow(COMPOSABLE_COW);
    twapHandler = TWAP_HANDLER;
  }
}
