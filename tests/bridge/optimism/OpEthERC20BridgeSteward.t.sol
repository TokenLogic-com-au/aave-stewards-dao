// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";

import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3Optimism, AaveV3OptimismAssets} from "aave-address-book/AaveV3Optimism.sol";
import {GovernanceV3Optimism} from "aave-address-book/GovernanceV3Optimism.sol";

import {OpEthERC20BridgeSteward} from "src/bridge/optimism/OpEthERC20BridgeSteward.sol";
import {IOpEthERC20BridgeSteward} from "src/bridge/optimism/interfaces/IOpEthERC20BridgeSteward.sol";

/**
 * @dev Test for OpEthERC20BridgeSteward contract
 * command: forge test -vvv --match-path tests/bridge/optimism/OpEthERC20BridgeSteward.t.sol
 */
contract OpEthERC20BridgeStewardTest is Test {
    OpEthERC20BridgeSteward steward;

    address OWNER = makeAddr("owner");
    address GUARDIAN = makeAddr("guardian");

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("optimism"), 148_300_000);

        steward = new OpEthERC20BridgeSteward(OWNER, GUARDIAN);

        vm.startPrank(GovernanceV3Optimism.EXECUTOR_LVL_1);
        IAccessControl(address(AaveV3Optimism.COLLECTOR)).grantRole(
            bytes32("FUNDS_ADMIN"),
            address(steward)
        );
        vm.stopPrank();
    }

    function _fundCollectorUSDCe(uint256 amount) internal {
        deal(AaveV3OptimismAssets.USDC_UNDERLYING, address(AaveV3Optimism.COLLECTOR), amount);
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
        new OpEthERC20BridgeSteward(address(0), makeAddr("guardian"));
    }

    function test_revertsIf_guardianIsZeroAddress() public {
        vm.expectRevert(IOpEthERC20BridgeSteward.InvalidZeroAddress.selector);
        new OpEthERC20BridgeSteward(makeAddr("owner"), address(0));
    }

    function test_constructor() public {
        address owner = makeAddr("owner");
        address guardian = makeAddr("guardian");

        OpEthERC20BridgeSteward _steward = new OpEthERC20BridgeSteward(owner, guardian);

        assertEq(_steward.owner(), owner);
        assertEq(_steward.guardian(), guardian);
        assertEq(
            _steward.L2_STANDARD_BRIDGE(),
            0x4200000000000000000000000000000000000010
        );
        assertEq(_steward.MIN_GAS_LIMIT(), 250_000);
    }
}

contract SetTokenMappingTest is OpEthERC20BridgeStewardTest {
    function test_revertsIf_notOwner() public {
        vm.startPrank(GUARDIAN);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                GUARDIAN
            )
        );
        steward.setTokenMapping(AaveV3OptimismAssets.USDC_UNDERLYING, AaveV3EthereumAssets.USDC_UNDERLYING);
        vm.stopPrank();
    }

    function test_revertsIf_invalidZeroAddress_l2Token() public {
        vm.startPrank(OWNER);
        vm.expectRevert(IOpEthERC20BridgeSteward.InvalidZeroAddress.selector);
        steward.setTokenMapping(address(0), AaveV3EthereumAssets.USDC_UNDERLYING);
        vm.stopPrank();
    }

    function test_revertsIf_invalidZeroAddress_l1Token() public {
        vm.startPrank(OWNER);
        vm.expectRevert(IOpEthERC20BridgeSteward.InvalidZeroAddress.selector);
        steward.setTokenMapping(AaveV3OptimismAssets.USDC_UNDERLYING, address(0));
        vm.stopPrank();
    }

    function test_revertsIf_mappingAlreadySet() public {
        vm.startPrank(OWNER);
        steward.setTokenMapping(AaveV3OptimismAssets.USDC_UNDERLYING, AaveV3EthereumAssets.USDC_UNDERLYING);

        vm.expectRevert(IOpEthERC20BridgeSteward.TokenAlreadySet.selector);
        steward.setTokenMapping(AaveV3OptimismAssets.USDC_UNDERLYING, AaveV3EthereumAssets.USDC_UNDERLYING);
        vm.stopPrank();
    }

    function test_revertsIf_invalidL1Token() public {
        // Pair USDC.e (L2) with WETH (L1) — USDC.e.l1Token() returns USDC mainnet, not WETH
        vm.startPrank(OWNER);
        vm.expectRevert(IOpEthERC20BridgeSteward.InvalidL1Token.selector);
        steward.setTokenMapping(AaveV3OptimismAssets.USDC_UNDERLYING, AaveV3EthereumAssets.WETH_UNDERLYING);
        vm.stopPrank();
    }

    function test_successful() public {
        vm.startPrank(OWNER);

        vm.expectEmit(true, true, true, true, address(steward));
        emit IOpEthERC20BridgeSteward.TokenMappingUpdated(
            AaveV3OptimismAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.USDC_UNDERLYING
        );

        steward.setTokenMapping(AaveV3OptimismAssets.USDC_UNDERLYING, AaveV3EthereumAssets.USDC_UNDERLYING);
        vm.stopPrank();

        assertEq(
            steward.tokenMapping(AaveV3OptimismAssets.USDC_UNDERLYING),
            AaveV3EthereumAssets.USDC_UNDERLYING
        );
    }
}

contract RemoveTokenMappingTest is OpEthERC20BridgeStewardTest {
    function test_revertsIf_notOwner() public {
        vm.startPrank(GUARDIAN);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                GUARDIAN
            )
        );
        steward.removeTokenMapping(AaveV3OptimismAssets.USDC_UNDERLYING);
        vm.stopPrank();
    }

    function test_revertsIf_mappingNotSet() public {
        vm.startPrank(OWNER);
        vm.expectRevert(IOpEthERC20BridgeSteward.TokenNotSet.selector);
        steward.removeTokenMapping(AaveV3OptimismAssets.USDC_UNDERLYING);
        vm.stopPrank();
    }

    function test_successful() public {
        vm.startPrank(OWNER);
        steward.setTokenMapping(AaveV3OptimismAssets.USDC_UNDERLYING, AaveV3EthereumAssets.USDC_UNDERLYING);
        assertEq(
            steward.tokenMapping(AaveV3OptimismAssets.USDC_UNDERLYING),
            AaveV3EthereumAssets.USDC_UNDERLYING
        );

        vm.expectEmit(true, false, false, false, address(steward));
        emit IOpEthERC20BridgeSteward.TokenMappingRemoved(AaveV3OptimismAssets.USDC_UNDERLYING);

        steward.removeTokenMapping(AaveV3OptimismAssets.USDC_UNDERLYING);
        vm.stopPrank();

        assertEq(steward.tokenMapping(AaveV3OptimismAssets.USDC_UNDERLYING), address(0));
    }
}

contract BridgeTest is OpEthERC20BridgeStewardTest {
    function _bridge_successful(address caller) internal {
        uint256 amount = 1_000e6;
        _fundCollectorUSDCe(amount);

        vm.prank(OWNER);
        steward.setTokenMapping(AaveV3OptimismAssets.USDC_UNDERLYING, AaveV3EthereumAssets.USDC_UNDERLYING);

        assertEq(
            IERC20(AaveV3OptimismAssets.USDC_UNDERLYING).balanceOf(address(steward)),
            0
        );

        vm.prank(caller);
        vm.expectEmit(true, true, true, true, address(steward));
        emit IOpEthERC20BridgeSteward.Bridge(
            AaveV3OptimismAssets.USDC_UNDERLYING,
            AaveV3EthereumAssets.USDC_UNDERLYING,
            amount,
            address(AaveV3Ethereum.COLLECTOR)
        );
        steward.bridge(AaveV3OptimismAssets.USDC_UNDERLYING, amount);

        assertEq(
            IERC20(AaveV3OptimismAssets.USDC_UNDERLYING).balanceOf(address(steward)),
            0
        );
        assertEq(
            IERC20(AaveV3OptimismAssets.USDC_UNDERLYING).allowance(address(steward), steward.L2_STANDARD_BRIDGE()),
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
        steward.bridge(AaveV3OptimismAssets.USDC_UNDERLYING, 1_000e6);
    }

    function test_revertsIf_tokenNotSet() public {
        vm.startPrank(OWNER);
        vm.expectRevert(IOpEthERC20BridgeSteward.TokenNotSet.selector);
        steward.bridge(AaveV3OptimismAssets.USDC_UNDERLYING, 1_000e6);
        vm.stopPrank();
    }

    function test_revertsIf_zeroAmount() public {
        vm.startPrank(OWNER);
        steward.setTokenMapping(AaveV3OptimismAssets.USDC_UNDERLYING, AaveV3EthereumAssets.USDC_UNDERLYING);
        vm.expectRevert(IOpEthERC20BridgeSteward.InvalidZeroAmount.selector);
        steward.bridge(AaveV3OptimismAssets.USDC_UNDERLYING, 0);
        vm.stopPrank();
    }

    function test_revertsIf_noBalance() public {
        vm.startPrank(OWNER);
        steward.setTokenMapping(AaveV3OptimismAssets.USDC_UNDERLYING, AaveV3EthereumAssets.USDC_UNDERLYING);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        steward.bridge(AaveV3OptimismAssets.USDC_UNDERLYING, 1_000e6);
        vm.stopPrank();
    }

    function test_successful_owner() public {
        _bridge_successful(OWNER);
    }

    function test_successful_guardian() public {
        _bridge_successful(GUARDIAN);
    }
}

contract RescueTokenTest is OpEthERC20BridgeStewardTest {
    function _rescueToken_successful(address caller) internal {
        uint256 rescueAmount = 1_000e18;
        deal(AaveV3OptimismAssets.WETH_UNDERLYING, address(steward), rescueAmount);

        uint256 initialCollectorBalance = IERC20(
            AaveV3OptimismAssets.WETH_UNDERLYING
        ).balanceOf(address(AaveV3Optimism.COLLECTOR));

        vm.prank(caller);
        vm.expectEmit(true, true, false, true, AaveV3OptimismAssets.WETH_UNDERLYING);
        emit IERC20.Transfer(address(steward), address(AaveV3Optimism.COLLECTOR), rescueAmount);
        steward.rescueToken(AaveV3OptimismAssets.WETH_UNDERLYING);

        assertEq(
            IERC20(AaveV3OptimismAssets.WETH_UNDERLYING).balanceOf(
                address(AaveV3Optimism.COLLECTOR)
            ),
            initialCollectorBalance + rescueAmount
        );
        assertEq(
            IERC20(AaveV3OptimismAssets.WETH_UNDERLYING).balanceOf(address(steward)),
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
        steward.rescueToken(AaveV3OptimismAssets.WETH_UNDERLYING);
    }

    function test_successful_owner() public {
        _rescueToken_successful(OWNER);
    }

    function test_successful_guardian() public {
        _rescueToken_successful(GUARDIAN);
    }
}

contract RescueEthTest is OpEthERC20BridgeStewardTest {
    function _rescueEth_successful(address caller) internal {
        uint256 rescueAmount = 1 ether;
        vm.deal(address(steward), rescueAmount);

        uint256 initialCollectorBalance = address(AaveV3Optimism.COLLECTOR).balance;

        vm.prank(caller);
        steward.rescueEth();

        assertEq(address(steward).balance, 0);
        assertEq(
            address(AaveV3Optimism.COLLECTOR).balance,
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

contract MaxRescueTest is OpEthERC20BridgeStewardTest {
    function test_maxRescue() public {
        assertEq(
            steward.maxRescue(AaveV3OptimismAssets.USDC_UNDERLYING),
            0
        );

        uint256 mintAmount = 1_000_000e6;
        deal(AaveV3OptimismAssets.USDC_UNDERLYING, address(steward), mintAmount);

        assertEq(
            steward.maxRescue(AaveV3OptimismAssets.USDC_UNDERLYING),
            mintAmount
        );
    }
}

contract BridgeEthTest is OpEthERC20BridgeStewardTest {
    function _bridgeEth_successful(address caller) internal {
        uint256 amount = 1 ether;
        vm.deal(caller, amount);

        vm.prank(caller);
        vm.expectEmit(true, false, false, true, address(steward));
        emit IOpEthERC20BridgeSteward.BridgeEth(amount, address(AaveV3Ethereum.COLLECTOR));
        steward.bridgeEth{value: amount}();

        assertEq(address(steward).balance, 0);
    }

    function test_revertsIf_invalidCaller() public {
        vm.deal(address(this), 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector,
                address(this)
            )
        );
        steward.bridgeEth{value: 1 ether}();
    }

    function test_revertsIf_zeroValue() public {
        vm.prank(OWNER);
        vm.expectRevert(IOpEthERC20BridgeSteward.InvalidZeroAmount.selector);
        steward.bridgeEth();
    }

    function test_successful_owner() public {
        _bridgeEth_successful(OWNER);
    }

    function test_successful_guardian() public {
        _bridgeEth_successful(GUARDIAN);
    }
}
