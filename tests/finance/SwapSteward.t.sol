// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AaveV3Arbitrum} from "aave-address-book/AaveV3Arbitrum.sol";
import {GovernanceV3Arbitrum} from "aave-address-book/GovernanceV3Arbitrum.sol";

import {OracleMarketOrder} from "src/finance/OracleMarketOrder.sol";
import {SwapSteward} from "src/finance/SwapSteward.sol";

/**
 * @dev Test for SwapSteward contract
 * command: forge test -vvv --match-path tests/finance/SwapSteward.t.sol
 */
contract SwapStewardTest is Test {
  // https://arbiscan.io/address/0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74
  address internal constant COMPOSABLE_COW = 0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74;

  // https://arbiscan.io/address/0x6cF1e9cA41f7611dEf408122793c358a3d11E5a5
  address internal constant TWAP_HANDLER = 0x6cF1e9cA41f7611dEf408122793c358a3d11E5a5;

  // https://arbiscan.io/address/0x9008D19f58AAbD9eD0D60971565AA8510560ab41
  address internal constant GPV2_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;

  // https://arbiscan.io/address/0xC92E8bdf79f0507f65a392b0ab4667716BFE0110
  address internal constant VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

  uint256 internal constant FORK_BLOCK = 512244730;
  bytes32 internal constant APP_DATA = keccak256("SwapSteward");

  address public guardian = makeAddr("guardian");
  address public alice = makeAddr("alice");
  address public limitOrderHandler = makeAddr("limitOrderHandler");

  OracleMarketOrder public marketOrderHandler;
  SwapSteward public steward;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("arbitrum"), FORK_BLOCK);

    marketOrderHandler = new OracleMarketOrder();
    steward = new SwapSteward(
      GovernanceV3Arbitrum.EXECUTOR_LVL_1,
      guardian,
      address(AaveV3Arbitrum.COLLECTOR),
      COMPOSABLE_COW,
      address(marketOrderHandler),
      limitOrderHandler,
      TWAP_HANDLER,
      VAULT_RELAYER,
      APP_DATA
    );
  }

  function test_constructor() public {}

  function test_revertsIf_collectorIsZeroAddress() public {}

  function test_revertsIf_composableCowIsZeroAddress() public {}

  function test_revertsIf_handlerIsZeroAddress() public {}

  function test_revertsIf_vaultRelayerIsZeroAddress() public {}

  function test_transferOwnership() public {}

  function test_updateGuardian_revertsIf_notOwnerOrGuardian() public {}

  function test_updateGuardian() public {}

  function test_rescueToken_revertsIf_notOwnerOrGuardian() public {}

  function test_rescueToken() public {}

  function test_rescueToken_amount() public {}

  function test_setSwappablePair_revertsIf_notOwner() public {}

  function test_setSwappablePair_revertsIf_sameToken() public {}

  function test_setSwappablePair() public {}

  function test_setTokenOracle_revertsIf_notOwner() public {}

  function test_setTokenOracle_revertsIf_zeroAddress() public {}

  function test_setTokenOracle_revertsIf_incompatibleDecimals() public {}

  function test_setTokenOracle_revertsIf_invalidAnswer() public {}

  function test_setTokenOracle() public {}

  function test_increaseTokenBudget_revertsIf_notOwner() public {}

  function test_increaseTokenBudget() public {}

  function test_decreaseTokenBudget_revertsIf_notOwner() public {}

  function test_decreaseTokenBudget_revertsIf_insufficientBudget() public {}

  function test_decreaseTokenBudget() public {}

  function test_swap_revertsIf_notOwnerOrGuardian() public {}

  function test_swap_revertsIf_zeroAmount() public {}

  function test_swap_revertsIf_unrecognizedPair() public {}

  function test_swap_revertsIf_oracleNotSet() public {}

  function test_swap_revertsIf_slippageAboveMax() public {}

  function test_swap_revertsIf_invalidPriceFeedAnswer() public {}

  function test_swap_revertsIf_budgetExceeded() public {}

  function test_swap_revertsIf_swapAlreadyPending() public {}

  function test_swap_success_ownerSkipsBudget() public {}

  function test_swap_success_guardianConsumesBudget() public {}

  function test_swap_success_maxAmount() public {}

  function test_swap_emitsSwapRequested() public {}

  function test_swap_setsPendingOrder() public {}

  function test_swap_approvesVaultRelayer() public {}

  function test_limitSwap_revertsIf_unrecognizedPair() public {}

  function test_limitSwap_revertsIf_swapAlreadyPending() public {}

  function test_limitSwap_success() public {}

  function test_twapSwap_revertsIf_unrecognizedPair() public {}

  function test_twapSwap_revertsIf_swapAlreadyPending() public {}

  function test_twapSwap_success() public {}

  function test_cancelSwap_revertsIf_notOwnerOrGuardian() public {}

  function test_cancelSwap_revertsIf_swapNotFound() public {}

  function test_cancelSwap_beforeFill() public {}

  function test_cancelSwap_afterPartialFill() public {}

  function test_cancelSwap_afterFill() public {}

  function test_cancelSwap_clearsPendingOrder() public {}

  function test_cancelSwap_zeroesRelayerAllowance() public {}

  function test_cancelSwap_removesOrderFromComposableCow() public {}

  function test_swap_afterCancel() public {}

  function test_isValidSignature_revertsIf_invalidHash() public {}

  function test_isValidSignature_revertsIf_orderCanceled() public {}

  function test_isValidSignature() public {}

  function test_getExpectedOut_revertsIf_oracleNotSet() public {}

  function test_getExpectedOut() public {}

  function test_settle() public {}

  function test_settle_revertsIf_worseBuyAmount() public {}

  function test_settle_sameValidToBucket() public {}

  function test_settle_revertsIf_afterBucketChange() public {}

  function test_settle_revertsIf_afterOracleRoundChange() public {}
}
