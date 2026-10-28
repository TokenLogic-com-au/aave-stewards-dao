// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AaveV3Base, AaveV3BaseAssets} from "aave-address-book/AaveV3Base.sol";
import {ChainlinkBase} from "aave-address-book/ChainlinkBase.sol";
import {GovernanceV3Base} from "aave-address-book/GovernanceV3Base.sol";
import {SwapStewardForkTestBase} from "tests/finance/swap/SwapStewardForkTestBase.sol";

contract SwapStewardForkBaseTest is SwapStewardForkTestBase {
  function _config() internal pure override returns (ChainConfig memory) {
    return ChainConfig({
      rpcAlias: "base",
      forkBlock: 52340779, // https://basescan.org/block/52340779
      executor: GovernanceV3Base.EXECUTOR_LVL_1,
      collector: address(AaveV3Base.COLLECTOR),
      sequencerUptimeFeed: ChainlinkBase.L2_Sequencer_Uptime_Status_Feed,
      fromToken: AaveV3BaseAssets.USDC_UNDERLYING,
      fromOracle: AaveV3BaseAssets.USDC_ORACLE,
      toToken: AaveV3BaseAssets.WETH_UNDERLYING,
      toOracle: AaveV3BaseAssets.WETH_ORACLE,
      swapAmount: 10e6,
      guardianBudget: 50e6,
      twapPartAmount: 5e6,
      twapMinPartLimit: 1e15
    });
  }
}
