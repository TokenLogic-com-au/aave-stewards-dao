// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SwapEscrow} from "src/finance/swap/SwapEscrow.sol";
import {SwapSteward} from "src/finance/swap/SwapSteward.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardConstructorTest is SwapStewardTestBase {
  function test_constructor_revertsWith_InvalidZeroAddress_collector() public {
    vm.expectRevert(ISwapSteward.InvalidZeroAddress.selector);
    _newSteward(address(0), address(composableCow), address(marketOrderHandler), twapHandler, vaultRelayer);
  }

  function test_constructor_revertsWith_InvalidZeroAddress_composableCow() public {
    vm.expectRevert(ISwapSteward.InvalidZeroAddress.selector);
    _newSteward(collector, address(0), address(marketOrderHandler), twapHandler, vaultRelayer);
  }

  function test_constructor_revertsWith_InvalidZeroAddress_marketOrderHandler() public {
    vm.expectRevert(ISwapSteward.InvalidZeroAddress.selector);
    _newSteward(collector, address(composableCow), address(0), twapHandler, vaultRelayer);
  }

  function test_constructor_revertsWith_InvalidZeroAddress_twapHandler() public {
    vm.expectRevert(ISwapSteward.InvalidZeroAddress.selector);
    _newSteward(collector, address(composableCow), address(marketOrderHandler), address(0), vaultRelayer);
  }

  function test_constructor_revertsWith_InvalidZeroAddress_vaultRelayer() public {
    vm.expectRevert(ISwapSteward.InvalidZeroAddress.selector);
    _newSteward(collector, address(composableCow), address(marketOrderHandler), twapHandler, address(0));
  }

  function test_constructor_allowsZeroGuardianAndSequencerFeed() public {
    SwapSteward stewardZeroGuardian = new SwapSteward(
      executor,
      address(0),
      collector,
      address(composableCow),
      address(marketOrderHandler),
      twapHandler,
      vaultRelayer,
      address(0)
    );

    assertEq(stewardZeroGuardian.guardian(), address(0));
    assertEq(stewardZeroGuardian.SEQUENCER_UPTIME_FEED(), address(0));
  }

  function test_constructor() public {
    address sequencerFeed = makeAddr("sequencerFeed");

    SwapSteward deployed = new SwapSteward(
      executor,
      guardian,
      collector,
      address(composableCow),
      address(marketOrderHandler),
      twapHandler,
      vaultRelayer,
      sequencerFeed
    );
    SwapEscrow implementation = SwapEscrow(deployed.SWAP_ESCROW_IMPLEMENTATION());

    assertEq(deployed.owner(), executor);
    assertEq(deployed.guardian(), guardian);
    assertEq(deployed.COLLECTOR(), collector);
    assertEq(address(deployed.COMPOSABLE_COW()), address(composableCow));
    assertEq(deployed.MARKET_ORDER_HANDLER(), address(marketOrderHandler));
    assertEq(deployed.TWAP_HANDLER(), twapHandler);
    assertEq(deployed.SEQUENCER_UPTIME_FEED(), sequencerFeed);
    assertEq(implementation.STEWARD(), address(deployed));
    assertEq(implementation.VAULT_RELAYER(), vaultRelayer);
    assertEq(address(implementation.COMPOSABLE_COW()), address(composableCow));
    assertEq(deployed.MAX_SLIPPAGE(), MAX_SLIPPAGE);
    assertEq(deployed.ORDER_LIFETIME(), 1 days);
    assertEq(deployed.SEQUENCER_GRACE_PERIOD(), 1 hours);
    assertEq(deployed.APP_DATA(), APP_DATA);
  }

  function _newSteward(
    address collector_,
    address composableCow_,
    address marketOrderHandler_,
    address twapHandler_,
    address vaultRelayer_
  ) internal returns (SwapSteward) {
    return new SwapSteward(
      executor, guardian, collector_, composableCow_, marketOrderHandler_, twapHandler_, vaultRelayer_, address(0)
    );
  }
}
