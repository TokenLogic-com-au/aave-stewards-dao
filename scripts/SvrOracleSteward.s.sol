// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, Create2Utils} from "solidity-utils/contracts/utils/ScriptUtils.sol";
import {ChainIds} from "solidity-utils/contracts/utils/ChainHelpers.sol";
import {MiscAvalanche} from "aave-address-book/MiscAvalanche.sol";
import {MiscBNB} from "aave-address-book/MiscBNB.sol";
import {MiscEthereum} from "aave-address-book/MiscEthereum.sol";
import {MiscPolygon} from "aave-address-book/MiscPolygon.sol";
import {GovernanceV3Avalanche} from "aave-address-book/GovernanceV3Avalanche.sol";
import {GovernanceV3BNB} from "aave-address-book/GovernanceV3BNB.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {GovernanceV3Polygon} from "aave-address-book/GovernanceV3Polygon.sol";
import {AaveV3Avalanche} from "aave-address-book/AaveV3Avalanche.sol";
import {AaveV3BNB} from "aave-address-book/AaveV3BNB.sol";
import {AaveV3Ethereum} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3Polygon} from "aave-address-book/AaveV3Polygon.sol";
import {IPoolAddressesProvider} from "aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol";
import {SvrOracleSteward, ISvrOracleSteward} from "../src/risk/SvrOracleSteward.sol";

library DeploySvrOracleSteward_Lib {
  function _deploy(IPoolAddressesProvider provider, address admin, address guardian)
    internal
    returns (SvrOracleSteward)
  {
    return SvrOracleSteward(
      Create2Utils.create2Deploy("v1", type(SvrOracleSteward).creationCode, abi.encode(provider, admin, guardian))
    );
  }

  function _deployMainnet() internal returns (SvrOracleSteward) {
    return _deploy(
      AaveV3Ethereum.POOL_ADDRESSES_PROVIDER, GovernanceV3Ethereum.EXECUTOR_LVL_1, MiscEthereum.PROTOCOL_GUARDIAN
    );
  }

  function _deployBNB() internal returns (SvrOracleSteward) {
    return _deploy(AaveV3BNB.POOL_ADDRESSES_PROVIDER, GovernanceV3BNB.EXECUTOR_LVL_1, MiscBNB.PROTOCOL_GUARDIAN);
  }

  function _deployAvalanche() internal returns (SvrOracleSteward) {
    return _deploy(
      AaveV3Avalanche.POOL_ADDRESSES_PROVIDER, GovernanceV3Avalanche.EXECUTOR_LVL_1, MiscAvalanche.PROTOCOL_GUARDIAN
    );
  }

  function _deployPolygon() internal returns (SvrOracleSteward) {
    return
      _deploy(AaveV3Polygon.POOL_ADDRESSES_PROVIDER, GovernanceV3Polygon.EXECUTOR_LVL_1, MiscPolygon.PROTOCOL_GUARDIAN);
  }
}

contract Deploy is Script {
  function run() external {
    vm.startBroadcast();
    if (block.chainid == ChainIds.MAINNET) {
      DeploySvrOracleSteward_Lib._deployMainnet();
    } else if (block.chainid == ChainIds.BNB) {
      DeploySvrOracleSteward_Lib._deployBNB();
    } else if (block.chainid == ChainIds.AVALANCHE) {
      DeploySvrOracleSteward_Lib._deployAvalanche();
    } else if (block.chainid == ChainIds.POLYGON) {
      DeploySvrOracleSteward_Lib._deployPolygon();
    }
  }
}
