// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, Create2Utils} from "solidity-utils/contracts/utils/ScriptUtils.sol";
import {ChainIds} from "solidity-utils/contracts/utils/ChainHelpers.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {GovernanceV3Arbitrum} from "aave-address-book/GovernanceV3Arbitrum.sol";
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

contract Deploy is Script {
  // Guardian: Finance Steward Safe, 2-of-3. Same address, threshold and owners on Ethereum and Arbitrum.
  // https://app.safe.global/home?safe=eth:0x22740deBa78d5a0c24C58C740e3715ec29de1bFa
  // https://app.safe.global/home?safe=arb1:0x22740deBa78d5a0c24C58C740e3715ec29de1bFa
  // https://etherscan.io/address/0x22740deBa78d5a0c24C58C740e3715ec29de1bFa
  // https://arbiscan.io/address/0x22740deBa78d5a0c24C58C740e3715ec29de1bFa

  // Signers are nested Safes:
  // Safe 2-of-5 - TokenLogic - 0x9DE1d45e2786b03498289959203F25b29B4D1193
  //   https://etherscan.io/address/0x9DE1d45e2786b03498289959203F25b29B4D1193
  //   https://arbiscan.io/address/0x9DE1d45e2786b03498289959203F25b29B4D1193
  // Safe 2-of-6 - Aave Labs - 0x4b752551fC6345A7de82F76fd7a5015CA16d1a74
  //   https://etherscan.io/address/0x4b752551fC6345A7de82F76fd7a5015CA16d1a74
  //   https://arbiscan.io/address/0x4b752551fC6345A7de82F76fd7a5015CA16d1a74
  // Safe 1-of-3 - LlamaRisk - 0xb291232F480F41c75802C4a60F1D2AC03404Afef
  //   https://etherscan.io/address/0xb291232F480F41c75802C4a60F1D2AC03404Afef
  //   https://arbiscan.io/address/0xb291232F480F41c75802C4a60F1D2AC03404Afef
  address internal constant FINANCE_STEWARD_SAFE = 0x22740deBa78d5a0c24C58C740e3715ec29de1bFa;

  /// https://etherscan.io/address/0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74#code
  /// https://arbiscan.io/address/0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74#code
  address internal constant COMPOSABLE_COW = 0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74;
  /// https://etherscan.io/address/0x6cF1e9cA41f7611dEf408122793c358a3d11E5a5#code
  /// https://arbiscan.io/address/0x6cF1e9cA41f7611dEf408122793c358a3d11E5a5#code
  address internal constant TWAP_HANDLER = 0x6cF1e9cA41f7611dEf408122793c358a3d11E5a5;
  /// https://etherscan.io/address/0xC92E8bdf79f0507f65a392b0ab4667716BFE0110#code
  /// https://arbiscan.io/address/0xC92E8bdf79f0507f65a392b0ab4667716BFE0110#code
  address internal constant VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

  function run() external {
    vm.startBroadcast();
    if (block.chainid == ChainIds.MAINNET) {
      DeploymentLibrary._deploySwapSteward(
        GovernanceV3Ethereum.EXECUTOR_LVL_1,
        FINANCE_STEWARD_SAFE,
        address(AaveV3Ethereum.COLLECTOR),
        COMPOSABLE_COW,
        DeploymentLibrary._deployOracleMarketOrder(),
        TWAP_HANDLER,
        VAULT_RELAYER,
        address(0)
      );
    } else if (block.chainid == ChainIds.ARBITRUM) {
      DeploymentLibrary._deploySwapSteward(
        GovernanceV3Arbitrum.EXECUTOR_LVL_1,
        FINANCE_STEWARD_SAFE,
        address(AaveV3Arbitrum.COLLECTOR),
        COMPOSABLE_COW,
        DeploymentLibrary._deployOracleMarketOrder(),
        TWAP_HANDLER,
        VAULT_RELAYER,
        ChainlinkArbitrum.L2_Sequencer_Uptime_Status_Feed
      );
    } else {
      revert("UNSUPPORTED_CHAIN");
    }
    vm.stopBroadcast();
  }
}
