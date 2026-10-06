// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {OracleMarketOrder} from "src/finance/OracleMarketOrder.sol";

/**
 * @dev Test for OracleMarketOrder handler
 * command: forge test -vvv --match-path tests/finance/OracleMarketOrder.t.sol
 */
contract OracleMarketOrderTest is Test {
  uint256 internal constant FORK_BLOCK = 512244730;

  OracleMarketOrder public handler;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("arbitrum"), FORK_BLOCK);

    handler = new OracleMarketOrder();
  }

  function test_supportsInterface() public {}

  function test_getTradeableOrder() public {}

  function test_getTradeableOrder_decimals() public {}

  function test_getTradeableOrder_receiverIsStaticInputReceiver() public {}

  function test_getTradeableOrder_feeAmountIsZero() public {}

  function test_getTradeableOrder_appDataPinned() public {}

  function test_fuzz_getTradeableOrder_slippage() public {}

  function test_getTradeableOrder_slippageCap() public {}

  function test_getTradeableOrder_validToBucketed() public {}

  function test_getTradeableOrder_revertsIf_invalidPrice() public {}

  function test_getTradeableOrder_revertsIf_zeroBuyAmount() public {}

  function test_getTradeableOrder_revertsIf_sequencerDown() public {}

  function test_getTradeableOrder_revertsIf_gracePeriodNotOver() public {}

  function test_getTradeableOrder_noSequencerFeed() public {}

  function test_verify() public {}

  function test_verify_revertsIf_invalidHash() public {}

  function test_verify_hashStableWithinBucket() public {}

  function test_verify_revertsIf_afterBucketChange() public {}

  function test_verify_revertsIf_afterOracleRoundChange() public {}
}
