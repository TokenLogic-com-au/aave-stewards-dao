// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {AaveV3Arbitrum} from "aave-address-book/AaveV3Arbitrum.sol";
import {AaveV3Ethereum} from "aave-address-book/AaveV3Ethereum.sol";
import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";
import {ChainIds} from "solidity-utils/contracts/utils/ChainHelpers.sol";
import {RescuableBase, IRescuableBase} from "solidity-utils/contracts/utils/RescuableBase.sol";

import {IArbEthERC20BridgeSteward} from "./interfaces/IArbEthERC20BridgeSteward.sol";
import {IL2GatewayRouter} from "./interfaces/IL2GatewayRouter.sol";
import {IArbSys} from "./interfaces/IArbSys.sol";
import {IOutbox} from "./interfaces/IOutbox.sol";

/**
 * @title ArbEthERC20BridgeSteward
 * @author efecarranza.eth (TokenLogic)
 * @notice Bridges funds held in Arbitrum's Collector to Mainnet's Collector.
 *
 * -- Security Considerations
 *
 * Bridging is routed through the Arbitrum L2 Gateway Router, which resolves the correct gateway
 * per token. Governance must only allowlist tokens supported by the standard bridge. Tokens that
 * rely on custom bridges or external protocols must NOT be added to the token mapping:
 *
 * - Native USDC: Bridged via Circle's CCTP, not through the standard bridge.
 * - wstETH: Uses a custom bridge maintained by Lido.
 *
 * For the full list of token gateways, see the Arbitrum L2 Gateway Router on Arbiscan:
 * https://arbiscan.io/address/0x5288c571Fd7aD117beA99bF60FE0846C4E84F933
 *
 * -- Permissions
 * The contract implements OwnableWithGuardian.
 * The owner will always be the respective network Level 1 Executor (governance).
 * The guardian role will be given to a Financial Service provider of the DAO (AFC).
 *
 * While the permitted Service Provider will have full operational control within the
 * governance-defined token allowlist, the allowed actions are limited by the contract itself.
 * All token interactions start and end on the Collector, so no funds ever leave the DAO's
 * possession at any point in time.
 */
contract ArbEthERC20BridgeSteward is
    IArbEthERC20BridgeSteward,
    OwnableWithGuardian,
    RescuableBase
{
    using SafeERC20 for IERC20;

    /// @inheritdoc IArbEthERC20BridgeSteward
    address public immutable L2_GATEWAY_ROUTER =
        0x5288c571Fd7aD117beA99bF60FE0846C4E84F933;

    /// @inheritdoc IArbEthERC20BridgeSteward
    address public constant MAINNET_OUTBOX =
        0x0B9857ae2D4A3DBe74ffE1d7DF045bb7F96E4840;

    /// @notice Arbitrum system precompile (same address on every Arbitrum chain).
    address public constant ARB_SYS =
        0x0000000000000000000000000000000000000064;

    /// @inheritdoc IArbEthERC20BridgeSteward
    mapping(address l2Token => address l1Token) public config;

    /// @param initialOwner The owner of the contract upon deployment
    /// @param initialGuardian The guardian of the contract upon deployment
    constructor(
        address initialOwner,
        address initialGuardian
    ) OwnableWithGuardian(initialOwner, initialGuardian) {
        require(initialGuardian != address(0), InvalidZeroAddress());
    }

    receive() external payable {}

    /// @inheritdoc IArbEthERC20BridgeSteward
    function bridge(
        address token,
        uint256 amount
    ) external onlyOwnerOrGuardian {
        require(block.chainid == ChainIds.ARBITRUM, InvalidChain());
        require(amount > 0, InvalidZeroAmount());

        address l1Token = config[token];
        require(l1Token != address(0), TokenNotSet());

        ICollector(address(AaveV3Arbitrum.COLLECTOR)).transfer(IERC20(token), address(this), amount);

        address gateway = IL2GatewayRouter(L2_GATEWAY_ROUTER).getGateway(l1Token);
        IERC20(token).forceApprove(gateway, amount);

        IL2GatewayRouter(L2_GATEWAY_ROUTER).outboundTransfer(
            l1Token,
            address(AaveV3Ethereum.COLLECTOR),
            amount,
            ""
        );

        IERC20(token).forceApprove(gateway, 0);

        emit Bridge(token, l1Token, amount, address(AaveV3Ethereum.COLLECTOR));
    }

    /// @inheritdoc IArbEthERC20BridgeSteward
    function bridgeEth(uint256 amount) external onlyOwnerOrGuardian {
        require(block.chainid == ChainIds.ARBITRUM, InvalidChain());
        require(amount > 0, InvalidZeroAmount());
        require(address(this).balance >= amount, InsufficientBalance());

        IArbSys(ARB_SYS).withdrawEth{value: amount}(address(AaveV3Ethereum.COLLECTOR));

        emit BridgeEth(amount, address(AaveV3Ethereum.COLLECTOR));
    }

    /// @inheritdoc IArbEthERC20BridgeSteward
    function setTokenMapping(
        address l2Token,
        address l1Token
    ) external onlyOwner {
        require(block.chainid == ChainIds.ARBITRUM, InvalidChain());
        require(
            l2Token != address(0) && l1Token != address(0),
            InvalidZeroAddress()
        );
        require(config[l2Token] == address(0), TokenAlreadySet());
        require(
            IL2GatewayRouter(L2_GATEWAY_ROUTER).calculateL2TokenAddress(l1Token) == l2Token,
            InvalidL2Token()
        );

        config[l2Token] = l1Token;
        emit TokenMappingUpdated(l2Token, l1Token);
    }

    /// @inheritdoc IArbEthERC20BridgeSteward
    function removeTokenMapping(address l2Token) external onlyOwner {
        require(block.chainid == ChainIds.ARBITRUM, InvalidChain());
        require(config[l2Token] != address(0), TokenNotSet());

        delete config[l2Token];
        emit RemovedTokenMapping(l2Token);
    }

    /// @inheritdoc IArbEthERC20BridgeSteward
    function executeOutbox(
        bytes32[] calldata proof,
        uint256 index,
        address l2Sender,
        address to,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        uint256 value,
        bytes calldata data
    ) external {
        require(block.chainid == ChainIds.MAINNET, InvalidChain());

        IOutbox(MAINNET_OUTBOX).executeTransaction(
            proof,
            index,
            l2Sender,
            to,
            l2Block,
            l1Block,
            l2Timestamp,
            value,
            data
        );

        emit OutboxExecuted(l2Sender, to);
    }

    /// @inheritdoc IArbEthERC20BridgeSteward
    function rescueToken(address token) external onlyOwnerOrGuardian {
        _emergencyTokenTransfer(token, address(AaveV3Arbitrum.COLLECTOR), type(uint256).max);
    }

    /// @inheritdoc IArbEthERC20BridgeSteward
    function rescueEth() external onlyOwnerOrGuardian {
        _emergencyEtherTransfer(address(AaveV3Arbitrum.COLLECTOR), address(this).balance);
    }

    /// @inheritdoc IRescuableBase
    function maxRescue(
        address token
    ) public view override(RescuableBase) returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
