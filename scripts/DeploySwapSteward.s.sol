// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, Create2Utils} from "solidity-utils/contracts/utils/ScriptUtils.sol";
import {ChainIds} from "solidity-utils/contracts/utils/ChainHelpers.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {GovernanceV3Arbitrum} from "aave-address-book/GovernanceV3Arbitrum.sol";
import {MiscEthereum} from "aave-address-book/MiscEthereum.sol";
import {MiscArbitrum} from "aave-address-book/MiscArbitrum.sol";
import {AaveV3Ethereum} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3Arbitrum} from "aave-address-book/AaveV3Arbitrum.sol";
import {ChainlinkArbitrum} from "aave-address-book/ChainlinkArbitrum.sol";
import {SwapSteward} from "src/finance/swap/SwapSteward.sol";
import {OracleMarketOrder} from "src/finance/swap/OracleMarketOrder.sol";

library DeploymentLibrary {
  function _deployOracleMarketOrder() internal returns (address) {
    return Create2Utils.create2Deploy("v1", type(OracleMarketOrder).creationCode);
  }

  function _deploySwapSteward(
    address initialOwner,
    address initialGuardian,
    address collector,
    address composableCow,
    address marketOrderHandler,
    address twapHandler,
    address vaultRelayer,
    address sequencerUptimeFeed
  ) internal returns (address) {
    return Create2Utils.create2Deploy(
      "v1",
      type(SwapSteward).creationCode,
      abi.encode(
        initialOwner,
        initialGuardian,
        collector,
        composableCow,
        marketOrderHandler,
        twapHandler,
        vaultRelayer,
        sequencerUptimeFeed
      )
    );
  }
}

// Canonical CoW deployments: the same CREATE2 address on every CoW chain, including Base (8453), which
// composable-cow networks.json does not list.
// https://etherscan.io/address/0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74#code
// https://arbiscan.io/address/0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74#code
address constant COMPOSABLE_COW = 0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74;
// https://etherscan.io/address/0x6cF1e9cA41f7611dEf408122793c358a3d11E5a5#code
// https://arbiscan.io/address/0x6cF1e9cA41f7611dEf408122793c358a3d11E5a5#code
address constant TWAP_HANDLER = 0x6cF1e9cA41f7611dEf408122793c358a3d11E5a5;
// https://etherscan.io/address/0xC92E8bdf79f0507f65a392b0ab4667716BFE0110#code
// https://arbiscan.io/address/0xC92E8bdf79f0507f65a392b0ab4667716BFE0110#code
address constant VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

contract Deploy is Script {
  function run() external {
    vm.startBroadcast();
    address executor;
    address guardian;
    address collector;
    address sequencerUptimeFeed;
    if (block.chainid == ChainIds.MAINNET) {
      executor = GovernanceV3Ethereum.EXECUTOR_LVL_1;
      guardian = MiscEthereum.AFC_SAFE;
      collector = address(AaveV3Ethereum.COLLECTOR);
      sequencerUptimeFeed = address(0);
    } else if (block.chainid == ChainIds.ARBITRUM) {
      executor = GovernanceV3Arbitrum.EXECUTOR_LVL_1;
      guardian = MiscArbitrum.AFC_SAFE;
      collector = address(AaveV3Arbitrum.COLLECTOR);
      sequencerUptimeFeed = ChainlinkArbitrum.L2_Sequencer_Uptime_Status_Feed;
    } else {
      revert("UNSUPPORTED_CHAIN");
    }
    DeploymentLibrary._deploySwapSteward(
      executor,
      guardian,
      collector,
      COMPOSABLE_COW,
      DeploymentLibrary._deployOracleMarketOrder(),
      TWAP_HANDLER,
      VAULT_RELAYER,
      sequencerUptimeFeed
    );
    vm.stopBroadcast();
  }
}
