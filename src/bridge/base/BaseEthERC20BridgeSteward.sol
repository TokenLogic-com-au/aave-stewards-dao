// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC165Checker} from "openzeppelin-contracts/contracts/utils/introspection/ERC165Checker.sol";
import {AaveV3Base} from "aave-address-book/AaveV3Base.sol";
import {AaveV3Ethereum} from "aave-address-book/AaveV3Ethereum.sol";
import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";
import {RescuableBase, IRescuableBase} from "solidity-utils/contracts/utils/RescuableBase.sol";

import {IBaseEthERC20BridgeSteward} from "./interfaces/IBaseEthERC20BridgeSteward.sol";
import {IL2StandardBridge} from "./interfaces/IL2StandardBridge.sol";
import {IOptimismMintableERC20} from "./interfaces/IOptimismMintableERC20.sol";
import {ILegacyMintableERC20} from "./interfaces/ILegacyMintableERC20.sol";

/**
 * @title BaseEthERC20BridgeSteward
 * @author efecarranza.eth (TokenLogic)
 * @notice Bridges ERC20 funds held in Base's Collector to Mainnet's Collector.
 *
 * -- Security Considerations
 *
 * Not all ERC20 tokens on Base are compatible with the Standard Bridge. Governance must
 * only allowlist tokens whose L2 representation uses the standard OptimismMintableERC20
 * pattern (e.g. USDbC). Tokens that rely on custom bridges or external protocols must NOT
 * be added to the token mapping:
 *
 * - DAI / USDS: Use MakerDAO/Sky's custom SkyLink (OP Token) bridge, not the Standard Bridge.
 * - Native USDC: Bridged via Circle's CCTP, not through the Standard Bridge.
 *
 * Incompatible tokens are also rejected on-chain: `setTokenMapping` validates the pair against
 * the token's `remoteToken()` / `l1Token()`, so a non-standard token cannot be mapped.
 *
 * For the full list of token bridges:
 * https://docs.base.org/chain/bridges
 *
 * -- Permissions
 * The contract implements OwnableWithGuardian.
 * The owner will always be the network Level 1 Executor (governance).
 * The guardian role will be given to a Financial Service provider of the DAO (AFC).
 *
 * While the permitted Service Provider will have full operational control,
 * the allowed actions are limited by the contract itself.
 * All token interactions start and end on the Collector, so no funds ever leave
 * the DAO's possession at any point in time.
 */
contract BaseEthERC20BridgeSteward is IBaseEthERC20BridgeSteward, OwnableWithGuardian, RescuableBase {
  using SafeERC20 for IERC20;

  /// @inheritdoc IBaseEthERC20BridgeSteward
  address public constant L2_STANDARD_BRIDGE = 0x4200000000000000000000000000000000000010;

  /// @inheritdoc IBaseEthERC20BridgeSteward
  uint32 public constant MIN_GAS_LIMIT = 250_000;

  /// @inheritdoc IBaseEthERC20BridgeSteward
  mapping(address l2Token => address l1Token) public tokenMapping;

  /// @param initialOwner The owner of the contract upon deployment
  /// @param initialGuardian The guardian of the contract upon deployment
  constructor(address initialOwner, address initialGuardian) OwnableWithGuardian(initialOwner, initialGuardian) {
    require(initialGuardian != address(0), InvalidZeroAddress());
  }

  /// @inheritdoc IBaseEthERC20BridgeSteward
  function bridge(address token, uint256 amount) external onlyOwnerOrGuardian {
    require(amount > 0, InvalidZeroAmount());

    address l1Token = tokenMapping[token];
    require(l1Token != address(0), TokenNotSet());

    ICollector(address(AaveV3Base.COLLECTOR)).transfer(IERC20(token), address(this), amount);

    IERC20(token).forceApprove(L2_STANDARD_BRIDGE, amount);
    IL2StandardBridge(L2_STANDARD_BRIDGE)
      .bridgeERC20To(token, l1Token, address(AaveV3Ethereum.COLLECTOR), amount, MIN_GAS_LIMIT, "");
    IERC20(token).forceApprove(L2_STANDARD_BRIDGE, 0);

    emit Bridge(token, l1Token, amount, address(AaveV3Ethereum.COLLECTOR));
  }

  /// @inheritdoc IBaseEthERC20BridgeSteward
  function setTokenMapping(address l2Token, address l1Token) external onlyOwner {
    require(l2Token != address(0) && l1Token != address(0), InvalidZeroAddress());
    require(tokenMapping[l2Token] == address(0), TokenAlreadySet());
    require(_isCorrectTokenPair(l2Token, l1Token), InvalidL1Token());

    tokenMapping[l2Token] = l1Token;
    emit TokenMappingUpdated(l2Token, l1Token);
  }

  /// @inheritdoc IBaseEthERC20BridgeSteward
  function removeTokenMapping(address l2Token) external onlyOwner {
    require(tokenMapping[l2Token] != address(0), TokenNotSet());

    delete tokenMapping[l2Token];
    emit RemovedTokenMapping(l2Token);
  }

  /// @inheritdoc IBaseEthERC20BridgeSteward
  function rescueToken(address token) external onlyOwnerOrGuardian {
    _emergencyTokenTransfer(token, address(AaveV3Base.COLLECTOR), type(uint256).max);
  }

  /// @inheritdoc IBaseEthERC20BridgeSteward
  function rescueEth() external onlyOwnerOrGuardian {
    _emergencyEtherTransfer(address(AaveV3Base.COLLECTOR), address(this).balance);
  }

  /// @inheritdoc IRescuableBase
  function maxRescue(address token) public view override(RescuableBase) returns (uint256) {
    return IERC20(token).balanceOf(address(this));
  }

  /// @dev Replicates the pair check used by the Base Standard Bridge.
  function _isCorrectTokenPair(address l2Token, address l1Token) internal view returns (bool) {
    if (ERC165Checker.supportsInterface(l2Token, type(ILegacyMintableERC20).interfaceId)) {
      return l1Token == ILegacyMintableERC20(l2Token).l1Token();
    } else {
      return l1Token == IOptimismMintableERC20(l2Token).remoteToken();
    }
  }
}
