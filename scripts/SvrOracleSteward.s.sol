// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, Create2Utils} from "solidity-utils/contracts/utils/ScriptUtils.sol";
import {ChainIds} from "solidity-utils/contracts/utils/ChainHelpers.sol";
import {MiscBNB} from "aave-address-book/MiscBNB.sol";
import {MiscEthereum} from "aave-address-book/MiscEthereum.sol";
import {GovernanceV3BNB} from "aave-address-book/GovernanceV3BNB.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {AaveV3BNB} from "aave-address-book/AaveV3BNB.sol";
import {AaveV3Ethereum} from "aave-address-book/AaveV3Ethereum.sol";
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
    return _deploy(
      AaveV3BNB.POOL_ADDRESSES_PROVIDER, GovernanceV3BNB.EXECUTOR_LVL_1, MiscBNB.PROTOCOL_GUARDIAN
    );
  }
}

contract Deploy is Script {
  function run() external {
    vm.startBroadcast();
    if (block.chainid == ChainIds.MAINNET) {
      DeploySvrOracleSteward_Lib._deployMainnet();
    } else if (block.chainid == ChainIds.BNB) {
      DeploySvrOracleSteward_Lib._deployBNB();
    }
  }
}
