// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AaveV3BNB, AaveV3BNBAssets} from "aave-address-book/AaveV3BNB.sol";
import {GovernanceV3BNB} from "aave-address-book/GovernanceV3BNB.sol";
import {SwapStewardForkTestBase} from "tests/finance/swap/SwapStewardForkTestBase.sol";

contract SwapStewardForkBnbTest is SwapStewardForkTestBase {
  function _config() internal pure override returns (ChainConfig memory) {
    return ChainConfig({
      rpcAlias: "bnb",
      forkBlock: 126616891, // https://bscscan.com/block/126616891
      executor: GovernanceV3BNB.EXECUTOR_LVL_1,
      collector: address(AaveV3BNB.COLLECTOR),
      sequencerUptimeFeed: address(0),
      fromToken: AaveV3BNBAssets.USDC_UNDERLYING,
      fromOracle: AaveV3BNBAssets.USDC_ORACLE,
      toToken: AaveV3BNBAssets.ETH_UNDERLYING,
      toOracle: AaveV3BNBAssets.ETH_ORACLE,
      otherToken: AaveV3BNBAssets.BTCB_UNDERLYING,
      otherOracle: AaveV3BNBAssets.BTCB_ORACLE,
      swapAmount: 10e18,
      guardianBudget: 50e18,
      twapPartAmount: 5e18,
      twapMinPartLimit: 1e15
    });
  }
}
