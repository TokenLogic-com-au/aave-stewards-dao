// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";
import {SwapStewardHandler} from "tests/finance/swap/SwapStewardHandler.sol";

/**
 * @dev Custody and budget invariants of SwapSteward on the non-fork fixture. Settlement is out of scope: no order is
 * filled, so every escrow either holds its funded and donated sell tokens or was cancelled and holds nothing.
 * Expected values come from the ghost state of SwapStewardHandler, which is computed from the handler inputs only.
 * command: forge test --match-path tests/finance/swap/SwapSteward.Invariant.t.sol -vv
 *
 * forge-config: default.invariant.runs = 128
 * forge-config: default.invariant.depth = 150
 * forge-config: default.invariant.fail-on-revert = true
 * forge-config: default.invariant.shrink-run-limit = 0
 * forge-config: default.invariant.show-metrics = true
 */
contract SwapStewardInvariantTest is SwapStewardTestBase {
  uint256 internal constant OTHER_COLLECTOR_BALANCE = 200e18;
  uint256 internal constant OTHER_GUARDIAN_BUDGET = 50e18;

  SwapStewardHandler internal handler;
  address[] internal sellTokens;

  function setUp() public override {
    super.setUp();

    deal(otherToken, collector, OTHER_COLLECTOR_BALANCE);
    vm.startPrank(executor);
    steward.setTokenOracle(otherToken, otherOracle);
    steward.setSwappablePair(otherToken, toToken, true);
    steward.increaseTokenBudget(otherToken, OTHER_GUARDIAN_BUDGET);
    vm.stopPrank();
    _approvePairsWithOtherToken();

    sellTokens.push(fromToken);
    sellTokens.push(otherToken);

    handler = new SwapStewardHandler(
      SwapStewardHandler.Setup({
        steward: steward,
        executor: executor,
        collector: collector,
        fromToken: fromToken,
        toToken: toToken,
        otherToken: otherToken,
        initialFromBudget: guardianBudget,
        initialOtherBudget: OTHER_GUARDIAN_BUDGET,
        initialFromBalance: COLLECTOR_BALANCE,
        initialOtherBalance: OTHER_COLLECTOR_BALANCE
      })
    );

    bytes4[] memory selectors = new bytes4[](7);
    selectors[0] = SwapStewardHandler.swap.selector;
    selectors[1] = SwapStewardHandler.twapSwap.selector;
    selectors[2] = SwapStewardHandler.cancelSwap.selector;
    selectors[3] = SwapStewardHandler.increaseTokenBudget.selector;
    selectors[4] = SwapStewardHandler.decreaseTokenBudget.selector;
    selectors[5] = SwapStewardHandler.donateToEscrow.selector;
    selectors[6] = SwapStewardHandler.warpForward.selector;

    targetContract(address(handler));
    targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
  }

  function invariant_budgetAccounting() public view {
    for (uint256 i; i < sellTokens.length; ++i) {
      address token = sellTokens[i];
      assertEq(
        steward.tokenBudget(token),
        handler.ghostIncreased(token) - handler.ghostDecreased(token) - handler.ghostGuardianSpent(token)
      );
    }
  }

  function invariant_custodyConservation() public view {
    uint256 count = handler.escrowCount();
    for (uint256 i; i < sellTokens.length; ++i) {
      address token = sellTokens[i];
      uint256 escrowBalances;
      uint256 returned;
      for (uint256 j; j < count; ++j) {
        (address escrow, SwapStewardHandler.Escrow memory record) = handler.escrowAt(j);
        escrowBalances += IERC20(token).balanceOf(escrow);
        if (!record.open && record.sellToken == token) returned += record.funded + record.donated;
      }

      assertEq(
        IERC20(token).balanceOf(collector) + escrowBalances + IERC20(token).balanceOf(address(steward)),
        handler.initialCollectorBalance(token) + handler.ghostDonated(token)
      );
      assertEq(
        IERC20(token).balanceOf(collector),
        handler.initialCollectorBalance(token) + returned - handler.ghostGuardianSpent(token)
          - handler.ghostOwnerSpent(token)
      );
    }
  }

  function invariant_openEscrows() public {
    uint256 count = handler.escrowCount();
    for (uint256 i; i < count; ++i) {
      (address escrow, SwapStewardHandler.Escrow memory record) = handler.escrowAt(i);
      if (!record.open) continue;

      (address swapToken, bytes32 swapHash) = steward.swaps(escrow);
      assertEq(swapToken, record.sellToken);
      assertEq(swapHash, record.orderHash);
      assertTrue(record.orderHash != bytes32(0));
      assertTrue(composableCow.singleOrders(escrow, record.orderHash));
      assertEq(IERC20(record.sellToken).balanceOf(escrow), record.funded + record.donated);
      assertEq(IERC20(record.sellToken).allowance(escrow, vaultRelayer), record.funded);
    }
  }

  function invariant_closedEscrows() public {
    uint256 count = handler.escrowCount();
    for (uint256 i; i < count; ++i) {
      (address escrow, SwapStewardHandler.Escrow memory record) = handler.escrowAt(i);
      if (record.open) continue;

      (, bytes32 swapHash) = steward.swaps(escrow);
      assertEq(swapHash, bytes32(0));
      assertFalse(composableCow.singleOrders(escrow, record.orderHash));
      assertEq(IERC20(record.sellToken).balanceOf(escrow), 0);
      assertEq(IERC20(record.sellToken).allowance(escrow, vaultRelayer), 0);
    }
  }

  function invariant_stewardHoldsNothing() public view {
    assertEq(IERC20(fromToken).balanceOf(address(steward)), 0);
    assertEq(IERC20(otherToken).balanceOf(address(steward)), 0);
    assertEq(IERC20(toToken).balanceOf(address(steward)), 0);
  }

  function afterInvariant() public view {
    assertGt(handler.swapCount(), 0);
    assertGt(handler.twapCount(), 0);
    assertGt(handler.cancelCount(), 0);
    assertGt(handler.donationCount(), 0);
  }
}
