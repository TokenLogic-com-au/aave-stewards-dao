// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {GovernanceV3Optimism} from "aave-address-book/GovernanceV3Optimism.sol";
import {GovernanceV3Polygon} from "aave-address-book/GovernanceV3Polygon.sol";
import {GovernanceV3Arbitrum} from "aave-address-book/GovernanceV3Arbitrum.sol";
import {GovernanceV3Plasma} from "aave-address-book/GovernanceV3Plasma.sol";
import {AaveV3Ethereum} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3Optimism} from "aave-address-book/AaveV3Optimism.sol";
import {AaveV3Polygon} from "aave-address-book/AaveV3Polygon.sol";
import {AaveV3Arbitrum} from "aave-address-book/AaveV3Arbitrum.sol";
import {AaveV3Plasma} from "aave-address-book/AaveV3Plasma.sol";
import {
  ArbitrumScript,
  OptimismScript,
  PolygonScript,
  PlasmaScript
} from "solidity-utils/contracts/utils/ScriptUtils.sol";

import {OFTBridgeSteward} from "src/bridges/oft/OFTBridgeSteward.sol";
import {OFTConstants} from "src/bridges/oft/OFTConstants.sol";

address constant TOKEN_LOGIC = 0x3765A685a401622C060E5D700D9ad89413363a91;
bytes32 constant SALT = "Aave Treasury OFT Bridge";

contract DeployOFTArbitrum is ArbitrumScript {
  function run() external broadcast {
    new OFTBridgeSteward{salt: SALT}(
      OFTConstants.ARBITRUM_USDT0_OFT, // USDT0 OFT (OUpgradeable)
      GovernanceV3Arbitrum.EXECUTOR_LVL_1, // owner
      TOKEN_LOGIC, // guardian
      address(AaveV3Arbitrum.COLLECTOR) // collector
    );
  }
}

contract DeployOFTPolygon is PolygonScript {
  function run() external broadcast {
    new OFTBridgeSteward{salt: SALT}(
      OFTConstants.POLYGON_USDT0_OFT, // USDT0 OFT (OUpgradeable)
      GovernanceV3Polygon.EXECUTOR_LVL_1, // owner
      TOKEN_LOGIC, // guardian
      address(AaveV3Polygon.COLLECTOR) // collector
    );
  }
}

contract DeployOFTOptimism is OptimismScript {
  function run() external broadcast {
    new OFTBridgeSteward{salt: SALT}(
      OFTConstants.OPTIMISM_USDT0_OFT, // USDT0 OFT (OUpgradeable)
      GovernanceV3Optimism.EXECUTOR_LVL_1, // owner
      TOKEN_LOGIC, // guardian
      address(AaveV3Optimism.COLLECTOR) // collector
    );
  }
}

contract DeployOFTPlasma is PlasmaScript {
  function run() external broadcast {
    new OFTBridgeSteward{salt: SALT}(
      OFTConstants.PLASMA_USDT0_OFT, // USDT0 OFT (OUpgradeable)
      GovernanceV3Plasma.EXECUTOR_LVL_1, // owner
      TOKEN_LOGIC, // guardian
      address(AaveV3Plasma.COLLECTOR) // collector
    );
  }
}
