// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";

import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3Arbitrum, AaveV3ArbitrumAssets} from "aave-address-book/AaveV3Arbitrum.sol";
import {GovernanceV3Arbitrum} from "aave-address-book/GovernanceV3Arbitrum.sol";

import {ArbEthERC20BridgeSteward} from "src/bridge/arbitrum/ArbEthERC20BridgeSteward.sol";
import {IArbEthERC20BridgeSteward} from "src/bridge/arbitrum/interfaces/IArbEthERC20BridgeSteward.sol";
import {IL2GatewayRouter} from "src/bridge/arbitrum/interfaces/IL2GatewayRouter.sol";
import {IOutbox} from "src/bridge/arbitrum/interfaces/IOutbox.sol";

import {ArbSysMock} from "./ArbSysMock.sol";

/**
 * @dev Test for ArbEthERC20BridgeSteward contract
 * command: forge test -vvv --match-path tests/bridge/arbitrum/ArbEthERC20BridgeSteward.t.sol
 */
contract ArbEthERC20BridgeStewardTest is Test {
    ArbEthERC20BridgeSteward steward;

    address OWNER = makeAddr("owner");
    address GUARDIAN = makeAddr("guardian");

    address constant L2_GATEWAY_ROUTER =
        0x5288c571Fd7aD117beA99bF60FE0846C4E84F933;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("arbitrum"), 320_000_000);

        steward = new ArbEthERC20BridgeSteward(OWNER, GUARDIAN);

        _etchArbSysMock();

        vm.startPrank(GovernanceV3Arbitrum.EXECUTOR_LVL_1);
        IAccessControl(address(AaveV3Arbitrum.COLLECTOR)).grantRole(
            bytes32("FUNDS_ADMIN"),
            address(steward)
        );
        vm.stopPrank();
    }

    function _etchArbSysMock() internal {
        ArbSysMock arbsys = new ArbSysMock();
        vm.etch(
            0x0000000000000000000000000000000000000064,
            address(arbsys).code
        );
    }

    /// @dev Resolves the canonical L2 representation of an L1 token via the live
    ///      Arbitrum Gateway Router on the fork.
    function _canonicalL2(address l1Token) internal view returns (address) {
        return IL2GatewayRouter(L2_GATEWAY_ROUTER).calculateL2TokenAddress(l1Token);
    }
}

contract ConstructorTest is Test {
    function test_revertsIf_ownerIsZeroAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableInvalidOwner.selector,
                address(0)
            )
        );
        new ArbEthERC20BridgeSteward(address(0), makeAddr("guardian"));
    }

    function test_revertsIf_guardianIsZeroAddress() public {
        vm.expectRevert(
            IArbEthERC20BridgeSteward.InvalidZeroAddress.selector
        );
        new ArbEthERC20BridgeSteward(makeAddr("owner"), address(0));
    }

    function test_constructor() public {
        address owner = makeAddr("owner");
        address guardian = makeAddr("guardian");

        ArbEthERC20BridgeSteward _steward = new ArbEthERC20BridgeSteward(
            owner,
            guardian
        );

        assertEq(_steward.owner(), owner);
        assertEq(_steward.guardian(), guardian);
    }
}

contract SetTokenMappingTest is ArbEthERC20BridgeStewardTest {
    function test_revertsIf_notOwner() public {
        address l1Token = AaveV3EthereumAssets.USDC_UNDERLYING;
        address l2Token = _canonicalL2(l1Token);

        vm.startPrank(GUARDIAN);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                GUARDIAN
            )
        );
        steward.setTokenMapping(l2Token, l1Token);
        vm.stopPrank();
    }

    function test_revertsIf_invalidZeroAddress_l2Token() public {
        vm.startPrank(OWNER);
        vm.expectRevert(
            IArbEthERC20BridgeSteward.InvalidZeroAddress.selector
        );
        steward.setTokenMapping(
            address(0),
            AaveV3EthereumAssets.USDC_UNDERLYING
        );
        vm.stopPrank();
    }

    function test_revertsIf_invalidZeroAddress_l1Token() public {
        address l1Token = AaveV3EthereumAssets.USDC_UNDERLYING;
        address l2Token = _canonicalL2(l1Token);

        vm.startPrank(OWNER);
        vm.expectRevert(
            IArbEthERC20BridgeSteward.InvalidZeroAddress.selector
        );
        steward.setTokenMapping(l2Token, address(0));
        vm.stopPrank();
    }

    function test_revertsIf_mappingAlreadySet() public {
        address l1Token = AaveV3EthereumAssets.USDC_UNDERLYING;
        address l2Token = _canonicalL2(l1Token);

        vm.startPrank(OWNER);
        steward.setTokenMapping(l2Token, l1Token);

        vm.expectRevert(IArbEthERC20BridgeSteward.TokenAlreadySet.selector);
        steward.setTokenMapping(l2Token, l1Token);
        vm.stopPrank();
    }

    function test_revertsIf_l2TokenMismatchesCanonical() public {
        address l1Token = AaveV3EthereumAssets.USDC_UNDERLYING;
        address wrongL2Token = AaveV3ArbitrumAssets.WETH_UNDERLYING;

        vm.startPrank(OWNER);
        vm.expectRevert(IArbEthERC20BridgeSteward.InvalidL2Token.selector);
        steward.setTokenMapping(wrongL2Token, l1Token);
        vm.stopPrank();
    }

    function test_successful() public {
        address l1Token = AaveV3EthereumAssets.USDC_UNDERLYING;
        address l2Token = _canonicalL2(l1Token);

        vm.startPrank(OWNER);

        vm.expectEmit(true, true, true, true, address(steward));
        emit IArbEthERC20BridgeSteward.TokenMappingUpdated(l2Token, l1Token);

        steward.setTokenMapping(l2Token, l1Token);
        vm.stopPrank();

        assertEq(steward.config(l2Token), l1Token);
    }
}

contract RemoveTokenMappingTest is ArbEthERC20BridgeStewardTest {
    function test_revertsIf_notOwner() public {
        vm.startPrank(GUARDIAN);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                GUARDIAN
            )
        );
        steward.removeTokenMapping(AaveV3ArbitrumAssets.USDC_UNDERLYING);
        vm.stopPrank();
    }

    function test_revertsIf_mappingNotSet() public {
        vm.startPrank(OWNER);
        vm.expectRevert(IArbEthERC20BridgeSteward.TokenNotSet.selector);
        steward.removeTokenMapping(AaveV3ArbitrumAssets.USDC_UNDERLYING);
        vm.stopPrank();
    }

    function test_successful() public {
        address l1Token = AaveV3EthereumAssets.USDC_UNDERLYING;
        address l2Token = _canonicalL2(l1Token);

        vm.startPrank(OWNER);
        steward.setTokenMapping(l2Token, l1Token);
        assertEq(steward.config(l2Token), l1Token);

        vm.expectEmit(true, false, false, false, address(steward));
        emit IArbEthERC20BridgeSteward.RemovedTokenMapping(l2Token);

        steward.removeTokenMapping(l2Token);
        vm.stopPrank();

        assertEq(steward.config(l2Token), address(0));
    }
}

contract BridgeTest is ArbEthERC20BridgeStewardTest {
    address l1Token = AaveV3EthereumAssets.USDC_UNDERLYING;
    address l2Token;

    function setUp() public override {
        super.setUp();
        l2Token = _canonicalL2(l1Token);
    }

    function _setMapping() internal {
        vm.prank(OWNER);
        steward.setTokenMapping(l2Token, l1Token);
    }

    function _bridge_successful(address caller) internal {
        uint256 amount = 1_000e6;
        deal(l2Token, address(AaveV3Arbitrum.COLLECTOR), amount);

        _setMapping();

        assertEq(IERC20(l2Token).balanceOf(address(steward)), 0);

        vm.prank(caller);
        vm.expectEmit(true, true, true, true, address(steward));
        emit IArbEthERC20BridgeSteward.Bridge(
            l2Token,
            l1Token,
            amount,
            address(AaveV3Ethereum.COLLECTOR)
        );
        steward.bridge(l2Token, amount);

        assertEq(IERC20(l2Token).balanceOf(address(steward)), 0);
        // approval is reset to 0 after the outboundTransfer call
        address gateway = IL2GatewayRouter(L2_GATEWAY_ROUTER).getGateway(l1Token);
        assertEq(IERC20(l2Token).allowance(address(steward), gateway), 0);
    }

    function test_revertsIf_invalidCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector,
                address(this)
            )
        );
        steward.bridge(l2Token, 1_000e6);
    }

    function test_revertsIf_tokenNotSet() public {
        vm.startPrank(OWNER);
        vm.expectRevert(IArbEthERC20BridgeSteward.TokenNotSet.selector);
        steward.bridge(l2Token, 1_000e6);
        vm.stopPrank();
    }

    function test_revertsIf_zeroAmount() public {
        _setMapping();
        vm.prank(OWNER);
        vm.expectRevert(IArbEthERC20BridgeSteward.InvalidZeroAmount.selector);
        steward.bridge(l2Token, 0);
    }

    function test_revertsIf_noBalance() public {
        deal(l2Token, address(AaveV3Arbitrum.COLLECTOR), 0);
        _setMapping();

        vm.prank(OWNER);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        steward.bridge(l2Token, 1_000e6);
    }

    function test_successful_owner() public {
        _bridge_successful(OWNER);
    }

    function test_successful_guardian() public {
        _bridge_successful(GUARDIAN);
    }
}

contract BridgeEthTest is ArbEthERC20BridgeStewardTest {
    function _bridgeEth_successful(address caller) internal {
        uint256 amount = 1 ether;
        vm.deal(address(steward), amount);

        vm.prank(caller);
        vm.expectEmit(true, false, false, true, address(steward));
        emit IArbEthERC20BridgeSteward.BridgeEth(amount, address(AaveV3Ethereum.COLLECTOR));
        steward.bridgeEth(amount);

        assertEq(address(steward).balance, 0);
    }

    function test_revertsIf_invalidCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector,
                address(this)
            )
        );
        steward.bridgeEth(1 ether);
    }

    function test_revertsIf_zeroAmount() public {
        vm.prank(OWNER);
        vm.expectRevert(IArbEthERC20BridgeSteward.InvalidZeroAmount.selector);
        steward.bridgeEth(0);
    }

    function test_successful_owner() public {
        _bridgeEth_successful(OWNER);
    }

    function test_successful_guardian() public {
        _bridgeEth_successful(GUARDIAN);
    }
}

contract ExecuteOutboxTest is ArbEthERC20BridgeStewardTest {
    function test_successful_anyoneCanCall() public {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(uint256(1));
        address l2Sender = makeAddr("l2Sender");
        address to = makeAddr("to");
        bytes memory data = hex"deadbeef";

        vm.chainId(1);

        // Mock the Outbox: any executeTransaction call returns successfully.
        vm.mockCall(
            steward.MAINNET_OUTBOX(),
            abi.encodeWithSelector(IOutbox.executeTransaction.selector),
            ""
        );
        // And confirm the steward actually invokes the Outbox with the supplied params.
        vm.expectCall(
            steward.MAINNET_OUTBOX(),
            abi.encodeWithSelector(
                IOutbox.executeTransaction.selector,
                proof,
                uint256(0),
                l2Sender,
                to,
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0),
                data
            )
        );

        vm.expectEmit(true, true, false, false, address(steward));
        emit IArbEthERC20BridgeSteward.OutboxExecuted(l2Sender, to);

        // Permissionless — call from a random EOA.
        steward.executeOutbox(proof, 0, l2Sender, to, 0, 0, 0, 0, data);
    }
}

contract RescueTokenTest is ArbEthERC20BridgeStewardTest {
    function _rescueToken_successful(address caller) internal {
        uint256 rescueAmount = 1_000e18;
        deal(AaveV3ArbitrumAssets.WETH_UNDERLYING, address(steward), rescueAmount);

        uint256 initialCollectorBalance = IERC20(
            AaveV3ArbitrumAssets.WETH_UNDERLYING
        ).balanceOf(address(AaveV3Arbitrum.COLLECTOR));

        vm.prank(caller);
        vm.expectEmit(true, true, false, true, AaveV3ArbitrumAssets.WETH_UNDERLYING);
        emit IERC20.Transfer(address(steward), address(AaveV3Arbitrum.COLLECTOR), rescueAmount);
        steward.rescueToken(AaveV3ArbitrumAssets.WETH_UNDERLYING);

        assertEq(
            IERC20(AaveV3ArbitrumAssets.WETH_UNDERLYING).balanceOf(
                address(AaveV3Arbitrum.COLLECTOR)
            ),
            initialCollectorBalance + rescueAmount
        );
        assertEq(
            IERC20(AaveV3ArbitrumAssets.WETH_UNDERLYING).balanceOf(
                address(steward)
            ),
            0
        );
    }

    function test_revertsIf_invalidCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector,
                address(this)
            )
        );
        steward.rescueToken(AaveV3ArbitrumAssets.WETH_UNDERLYING);
    }

    function test_successful_owner() public {
        _rescueToken_successful(OWNER);
    }

    function test_successful_guardian() public {
        _rescueToken_successful(GUARDIAN);
    }
}

contract RescueEthTest is ArbEthERC20BridgeStewardTest {
    function _rescueEth_successful(address caller) internal {
        uint256 rescueAmount = 1 ether;
        vm.deal(address(steward), rescueAmount);

        uint256 initialCollectorBalance = address(AaveV3Arbitrum.COLLECTOR).balance;

        vm.prank(caller);
        steward.rescueEth();

        assertEq(address(steward).balance, 0);
        assertEq(
            address(AaveV3Arbitrum.COLLECTOR).balance,
            initialCollectorBalance + rescueAmount
        );
    }

    function test_revertsIf_invalidCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector,
                address(this)
            )
        );
        steward.rescueEth();
    }

    function test_successful_owner() public {
        _rescueEth_successful(OWNER);
    }

    function test_successful_guardian() public {
        _rescueEth_successful(GUARDIAN);
    }
}

contract MaxRescueTest is ArbEthERC20BridgeStewardTest {
    function test_maxRescue() public {
        assertEq(
            steward.maxRescue(AaveV3ArbitrumAssets.USDC_UNDERLYING),
            0
        );

        uint256 mintAmount = 1_000_000e6;
        deal(
            AaveV3ArbitrumAssets.USDC_UNDERLYING,
            address(steward),
            mintAmount
        );

        assertEq(
            steward.maxRescue(AaveV3ArbitrumAssets.USDC_UNDERLYING),
            mintAmount
        );
    }
}
