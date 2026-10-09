// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AaveV3Arbitrum, AaveV3ArbitrumAssets} from "aave-address-book/AaveV3Arbitrum.sol";
import {ChainlinkArbitrum} from "aave-address-book/ChainlinkArbitrum.sol";
import {GovernanceV3Arbitrum} from "aave-address-book/GovernanceV3Arbitrum.sol";
import {SwapStewardForkTestBase} from "tests/finance/swap/SwapStewardForkTestBase.sol";

contract SwapStewardForkArbitrumTest is SwapStewardForkTestBase {
  function _config() internal pure override returns (ChainConfig memory) {
    return ChainConfig({
      rpcAlias: "arbitrum",
      forkBlock: 512244730, // https://arbiscan.io/block/512244730
      executor: GovernanceV3Arbitrum.EXECUTOR_LVL_1,
      collector: address(AaveV3Arbitrum.COLLECTOR),
      sequencerUptimeFeed: ChainlinkArbitrum.L2_Sequencer_Uptime_Status_Feed,
      fromToken: AaveV3ArbitrumAssets.USDCn_UNDERLYING,
      fromOracle: AaveV3ArbitrumAssets.USDCn_ORACLE,
      toToken: AaveV3ArbitrumAssets.WETH_UNDERLYING,
      toOracle: AaveV3ArbitrumAssets.WETH_ORACLE,
      swapAmount: 10e6,
      guardianBudget: 50e6,
      twapPartAmount: 5e6,
      twapMinPartLimit: 1e15
    });
  }
}
