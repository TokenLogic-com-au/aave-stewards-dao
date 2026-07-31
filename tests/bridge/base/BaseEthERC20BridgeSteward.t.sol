// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";

import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3Base, AaveV3BaseAssets} from "aave-address-book/AaveV3Base.sol";
import {GovernanceV3Base} from "aave-address-book/GovernanceV3Base.sol";

import {BaseEthERC20BridgeSteward} from "src/bridge/base/BaseEthERC20BridgeSteward.sol";
import {IBaseEthERC20BridgeSteward} from "src/bridge/base/interfaces/IBaseEthERC20BridgeSteward.sol";

/**
 * @dev Test for BaseEthERC20BridgeSteward contract
 * command: forge test -vvv --match-path tests/bridge/base/BaseEthERC20BridgeSteward.t.sol
 */
contract BaseEthERC20BridgeStewardTest is Test {
  BaseEthERC20BridgeSteward steward;

  address constant L2_TOKEN = AaveV3BaseAssets.USDbC_UNDERLYING;
  address constant L1_TOKEN = AaveV3EthereumAssets.USDC_UNDERLYING;

  address OWNER = makeAddr("owner");
  address GUARDIAN = makeAddr("guardian");

  function setUp() public virtual {
    vm.createSelectFork(vm.rpcUrl("base"), 30_000_000);

    steward = new BaseEthERC20BridgeSteward(OWNER, GUARDIAN);

    vm.startPrank(GovernanceV3Base.EXECUTOR_LVL_1);
    IAccessControl(address(AaveV3Base.COLLECTOR)).grantRole(bytes32("FUNDS_ADMIN"), address(steward));
    vm.stopPrank();
  }
}

contract ConstructorTest is Test {
  function test_revertsIf_ownerIsZeroAddress() public {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
    new BaseEthERC20BridgeSteward(address(0), makeAddr("guardian"));
  }

  function test_revertsIf_guardianIsZeroAddress() public {
    vm.expectRevert(IBaseEthERC20BridgeSteward.InvalidZeroAddress.selector);
    new BaseEthERC20BridgeSteward(makeAddr("owner"), address(0));
  }

  function test_constructor() public {
    address owner = makeAddr("owner");
    address guardian = makeAddr("guardian");

    BaseEthERC20BridgeSteward _steward = new BaseEthERC20BridgeSteward(owner, guardian);

    assertEq(_steward.owner(), owner, "owner should be set to constructor argument");
    assertEq(_steward.guardian(), guardian, "guardian should be set to constructor argument");
    assertEq(_steward.L2_STANDARD_BRIDGE(), 0x4200000000000000000000000000000000000010, "L2 standard bridge address mismatch");
    assertEq(_steward.MIN_GAS_LIMIT(), 250_000, "min gas limit mismatch");
  }
}

contract SetTokenMappingTest is BaseEthERC20BridgeStewardTest {
  function test_revertsIf_notOwner() public {
    vm.startPrank(GUARDIAN);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, GUARDIAN));
    steward.setTokenMapping(L2_TOKEN, L1_TOKEN);
    vm.stopPrank();
  }

  function test_revertsIf_invalidZeroAddress_l2Token() public {
    vm.startPrank(OWNER);
    vm.expectRevert(IBaseEthERC20BridgeSteward.InvalidZeroAddress.selector);
    steward.setTokenMapping(address(0), L1_TOKEN);
    vm.stopPrank();
  }

  function test_revertsIf_invalidZeroAddress_l1Token() public {
    vm.startPrank(OWNER);
    vm.expectRevert(IBaseEthERC20BridgeSteward.InvalidZeroAddress.selector);
    steward.setTokenMapping(L2_TOKEN, address(0));
    vm.stopPrank();
  }

  function test_revertsIf_mappingAlreadySet() public {
    vm.startPrank(OWNER);
    steward.setTokenMapping(L2_TOKEN, L1_TOKEN);

    vm.expectRevert(IBaseEthERC20BridgeSteward.TokenAlreadySet.selector);
    steward.setTokenMapping(L2_TOKEN, L1_TOKEN);
    vm.stopPrank();
  }

  function test_revertsIf_invalidL1Token() public {
    vm.startPrank(OWNER);
    vm.expectRevert(IBaseEthERC20BridgeSteward.InvalidL1Token.selector);
    steward.setTokenMapping(L2_TOKEN, AaveV3EthereumAssets.WETH_UNDERLYING);
    vm.stopPrank();
  }

  function test_successful() public {
    vm.startPrank(OWNER);
    vm.expectEmit(true, true, true, true, address(steward));
    emit IBaseEthERC20BridgeSteward.TokenMappingUpdated(L2_TOKEN, L1_TOKEN);
    steward.setTokenMapping(L2_TOKEN, L1_TOKEN);
    vm.stopPrank();

    assertEq(steward.tokenMapping(L2_TOKEN), L1_TOKEN, "token mapping should be set after setTokenMapping");
  }
}

contract RemoveTokenMappingTest is BaseEthERC20BridgeStewardTest {
  function test_revertsIf_notOwner() public {
    vm.startPrank(GUARDIAN);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, GUARDIAN));
    steward.removeTokenMapping(L2_TOKEN);
    vm.stopPrank();
  }

  function test_revertsIf_mappingNotSet() public {
    vm.startPrank(OWNER);
    vm.expectRevert(IBaseEthERC20BridgeSteward.TokenNotSet.selector);
    steward.removeTokenMapping(L2_TOKEN);
    vm.stopPrank();
  }

  function test_successful() public {
    vm.startPrank(OWNER);
    steward.setTokenMapping(L2_TOKEN, L1_TOKEN);
    assertEq(steward.tokenMapping(L2_TOKEN), L1_TOKEN, "token mapping should be set before removal");

    vm.expectEmit(true, false, false, false, address(steward));
    emit IBaseEthERC20BridgeSteward.RemovedTokenMapping(L2_TOKEN);
    steward.removeTokenMapping(L2_TOKEN);
    vm.stopPrank();

    assertEq(steward.tokenMapping(L2_TOKEN), address(0), "token mapping should be cleared after removal");
  }
}

contract BridgeTest is BaseEthERC20BridgeStewardTest {
  function _bridge_successful(address caller) internal {
    uint256 amount = 1_000e6;
    deal(L2_TOKEN, address(AaveV3Base.COLLECTOR), amount);

    vm.prank(OWNER);
    steward.setTokenMapping(L2_TOKEN, L1_TOKEN);

    assertEq(IERC20(L2_TOKEN).balanceOf(address(steward)), 0, "steward should hold no tokens before bridging");

    vm.prank(caller);
    vm.expectEmit(true, true, true, true, address(steward));
    emit IBaseEthERC20BridgeSteward.Bridge(L2_TOKEN, L1_TOKEN, amount, address(AaveV3Ethereum.COLLECTOR));
    steward.bridge(L2_TOKEN, amount);

    assertEq(IERC20(L2_TOKEN).balanceOf(address(steward)), 0, "steward should hold no tokens after bridging");
    assertEq(IERC20(L2_TOKEN).allowance(address(steward), steward.L2_STANDARD_BRIDGE()), 0, "bridge allowance should be reset to zero");
  }

  function test_revertsIf_invalidCaller() public {
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, address(this)));
    steward.bridge(L2_TOKEN, 1_000e6);
  }

  function test_revertsIf_tokenNotSet() public {
    vm.prank(OWNER);
    vm.expectRevert(IBaseEthERC20BridgeSteward.TokenNotSet.selector);
    steward.bridge(L2_TOKEN, 1_000e6);
  }

  function test_revertsIf_zeroAmount() public {
    vm.startPrank(OWNER);
    steward.setTokenMapping(L2_TOKEN, L1_TOKEN);
    vm.expectRevert(IBaseEthERC20BridgeSteward.InvalidZeroAmount.selector);
    steward.bridge(L2_TOKEN, 0);
    vm.stopPrank();
  }

  function test_revertsIf_noBalance() public {
    vm.startPrank(OWNER);
    steward.setTokenMapping(L2_TOKEN, L1_TOKEN);
    deal(L2_TOKEN, address(AaveV3Base.COLLECTOR), 0);
    vm.expectRevert();
    steward.bridge(L2_TOKEN, 1_000e6);
    vm.stopPrank();
  }

  function test_successful_owner() public {
    _bridge_successful(OWNER);
  }

  function test_successful_guardian() public {
    _bridge_successful(GUARDIAN);
  }
}

contract RescueTokenTest is BaseEthERC20BridgeStewardTest {
  function _rescueToken_successful(address caller) internal {
    uint256 rescueAmount = 1_000e18;
    deal(AaveV3BaseAssets.WETH_UNDERLYING, address(steward), rescueAmount);

    uint256 initialCollectorBalance = IERC20(AaveV3BaseAssets.WETH_UNDERLYING).balanceOf(address(AaveV3Base.COLLECTOR));

    vm.prank(caller);
    vm.expectEmit(true, true, false, true, AaveV3BaseAssets.WETH_UNDERLYING);
    emit IERC20.Transfer(address(steward), address(AaveV3Base.COLLECTOR), rescueAmount);
    steward.rescueToken(AaveV3BaseAssets.WETH_UNDERLYING);

    assertEq(
      IERC20(AaveV3BaseAssets.WETH_UNDERLYING).balanceOf(address(AaveV3Base.COLLECTOR)),
      initialCollectorBalance + rescueAmount,
      "collector should receive the rescued tokens"
    );
    assertEq(IERC20(AaveV3BaseAssets.WETH_UNDERLYING).balanceOf(address(steward)), 0, "steward should hold no tokens after rescue");
  }

  function test_revertsIf_invalidCaller() public {
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, address(this)));
    steward.rescueToken(AaveV3BaseAssets.WETH_UNDERLYING);
  }

  function test_successful_owner() public {
    _rescueToken_successful(OWNER);
  }

  function test_successful_guardian() public {
    _rescueToken_successful(GUARDIAN);
  }
}

contract RescueEthTest is BaseEthERC20BridgeStewardTest {
  function _rescueEth_successful(address caller) internal {
    uint256 rescueAmount = 1 ether;
    vm.deal(address(steward), rescueAmount);

    uint256 initialCollectorBalance = address(AaveV3Base.COLLECTOR).balance;

    vm.prank(caller);
    steward.rescueEth();

    assertEq(address(steward).balance, 0, "steward should hold no ETH after rescue");
    assertEq(address(AaveV3Base.COLLECTOR).balance, initialCollectorBalance + rescueAmount, "collector should receive the rescued ETH");
  }

  function test_revertsIf_invalidCaller() public {
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, address(this)));
    steward.rescueEth();
  }

  function test_successful_owner() public {
    _rescueEth_successful(OWNER);
  }

  function test_successful_guardian() public {
    _rescueEth_successful(GUARDIAN);
  }
}

contract MaxRescueTest is BaseEthERC20BridgeStewardTest {
  function test_maxRescue() public {
    assertEq(steward.maxRescue(L2_TOKEN), 0, "maxRescue should be zero when steward holds no tokens");

    uint256 mintAmount = 1_000_000e6;
    deal(L2_TOKEN, address(steward), mintAmount);

    assertEq(steward.maxRescue(L2_TOKEN), mintAmount, "maxRescue should equal the steward's token balance");
  }
}
