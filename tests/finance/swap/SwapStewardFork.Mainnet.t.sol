// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {SwapStewardForkTestBase} from "tests/finance/swap/SwapStewardForkTestBase.sol";

contract SwapStewardForkMainnetTest is SwapStewardForkTestBase {
  function _config() internal pure override returns (ChainConfig memory) {
    return ChainConfig({
      rpcAlias: "mainnet",
      forkBlock: 26148310, // https://etherscan.io/block/26148310
      executor: GovernanceV3Ethereum.EXECUTOR_LVL_1,
      collector: address(AaveV3Ethereum.COLLECTOR),
      sequencerUptimeFeed: address(0),
      fromToken: AaveV3EthereumAssets.USDC_UNDERLYING,
      fromOracle: AaveV3EthereumAssets.USDC_ORACLE,
      toToken: AaveV3EthereumAssets.WETH_UNDERLYING,
      toOracle: AaveV3EthereumAssets.WETH_ORACLE,
      swapAmount: 10e6,
      guardianBudget: 50e6,
      twapPartAmount: 5e6,
      twapMinPartLimit: 1e15
    });
  }
}
