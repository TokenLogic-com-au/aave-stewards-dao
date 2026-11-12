// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {IRescuable} from "solidity-utils/contracts/utils/Rescuable.sol";
import {GovernanceV3Ethereum} from "aave-address-book/GovernanceV3Ethereum.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV3EthereumLido} from "aave-address-book/AaveV3EthereumLido.sol";
import {AaveV3EthereumEtherFi, AaveV3EthereumEtherFiAssets} from "aave-address-book/AaveV3EthereumEtherFi.sol";
import {AaveV2Ethereum, AaveV2EthereumAssets} from "aave-address-book/AaveV2Ethereum.sol";
import {
  AaveV4Ethereum,
  AaveV4EthereumTokenizationSpokes,
  IHub,
  ITokenizationSpoke
} from "aave-address-book/AaveV4Ethereum.sol";
import {IHubBase} from "aave-v4/hub/interfaces/IHubBase.sol";
import {IERC20Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {CollectorUtils} from "aave-helpers/src/CollectorUtils.sol";
import {PoolExposureSteward, IPoolExposureSteward} from "src/finance/PoolExposureSteward.sol";

/**
 * @dev Tests for PoolSteward contract
 * command: forge test --match-path tests/finance/PoolExposureSteward.t.sol -vvv
 */
contract PoolExposureStewardTest is Test {
  event ApprovedV2Pool(address indexed pool);
  event ApprovedV3Pool(address indexed pool);
  event ApprovedTokenizationSpoke(address indexed tokenizationSpoke);
  event RevokedV2Pool(address indexed pool);
  event RevokedV3Pool(address indexed pool);
  event RevokedTokenizationSpoke(address indexed tokenizationSpoke);

  address public constant EXECUTOR = AaveV3Ethereum.ACL_ADMIN;
  address public constant guardian = address(82);
  address public alice = address(43);
  PoolExposureSteward public steward;

  ITokenizationSpoke public constant USDC_SPOKE = AaveV4EthereumTokenizationSpokes.CORE_USDC_TOKENIZATION_SPOKE;
  ITokenizationSpoke public constant USDT_SPOKE = AaveV4EthereumTokenizationSpokes.CORE_USDT_TOKENIZATION_SPOKE;
  ITokenizationSpoke public constant WETH_SPOKE = AaveV4EthereumTokenizationSpokes.CORE_WETH_TOKENIZATION_SPOKE;
  ITokenizationSpoke public constant GHO_SPOKE = AaveV4EthereumTokenizationSpokes.CORE_GHO_TOKENIZATION_SPOKE;
  ITokenizationSpoke public constant WBTC_SPOKE = AaveV4EthereumTokenizationSpokes.CORE_WBTC_TOKENIZATION_SPOKE;
  // CORE spoke left out of the steward deployment, used for the unapproved spoke paths
  ITokenizationSpoke public constant UNAPPROVED_SPOKE = AaveV4EthereumTokenizationSpokes.CORE_LINK_TOKENIZATION_SPOKE;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("mainnet"), 26134500); // https://etherscan.io/block/26134500

    address[] memory v2Pools = new address[](1);
    v2Pools[0] = address(AaveV2Ethereum.POOL);

    address[] memory v3Pools = new address[](3);
    v3Pools[0] = address(AaveV3Ethereum.POOL);
    v3Pools[1] = address(AaveV3EthereumEtherFi.POOL);
    v3Pools[2] = address(AaveV3EthereumLido.POOL);

    address[] memory tokenizationSpokes = new address[](5);
    tokenizationSpokes[0] = address(USDC_SPOKE);
    tokenizationSpokes[1] = address(USDT_SPOKE);
    tokenizationSpokes[2] = address(WETH_SPOKE);
    tokenizationSpokes[3] = address(GHO_SPOKE);
    tokenizationSpokes[4] = address(WBTC_SPOKE);

    steward = new PoolExposureSteward(
      GovernanceV3Ethereum.EXECUTOR_LVL_1,
      guardian,
      address(AaveV3Ethereum.COLLECTOR),
      v2Pools,
      v3Pools,
      tokenizationSpokes
    );

    vm.label(address(AaveV3Ethereum.COLLECTOR), "Collector");
    vm.label(alice, "Alice");
    vm.label(guardian, "Guardian");
    vm.label(EXECUTOR, "Executor");
    vm.label(address(steward), "PoolSteward");

    vm.prank(EXECUTOR);
    IAccessControl(address(AaveV3Ethereum.COLLECTOR)).grantRole("FUNDS_ADMIN", address(steward));

    deal(AaveV3EthereumAssets.USDC_UNDERLYING, address(AaveV3Ethereum.COLLECTOR), 1_000_000e6);
  }

  function _setAddCap(ITokenizationSpoke spoke, uint256 addCap) internal {
    address hub = spoke.hub();
    uint256 assetId = spoke.assetId();
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    AaveV4Ethereum.HUB_CONFIGURATOR
      .updateSpokeAddCap({hub: hub, assetId: assetId, spoke: address(spoke), addCap: addCap});
  }

  function _setSpokeHalted(ITokenizationSpoke spoke) internal {
    address hub = spoke.hub();
    uint256 assetId = spoke.assetId();
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    AaveV4Ethereum.HUB_CONFIGURATOR.updateSpokeHalted({hub: hub, assetId: assetId, spoke: address(spoke), halted: true});
  }

  /// @dev The first V2 action at the fork block mints pending reserve factor aTokens to the Collector
  /// so this realizes it before balances are measured
  function _accrueV2Treasury() internal {
    vm.prank(guardian);
    steward.withdrawV2(address(AaveV2Ethereum.POOL), AaveV2EthereumAssets.USDC_UNDERLYING, 1e6);
  }

  /// @dev Deals `amount` of the spoke's underlying to the Collector and deposits it through the steward
  function _depositToV4(ITokenizationSpoke spoke, uint256 amount) internal returns (uint256 shares) {
    deal(spoke.asset(), address(AaveV3Ethereum.COLLECTOR), amount);
    vm.prank(guardian);
    shares = steward.depositV4(address(spoke), amount);
  }

  /// @dev The steward must never hold funds, shares or allowances after an action
  function _assertStewardUntouched(ITokenizationSpoke spoke) internal view {
    assertEq(IERC20(spoke.asset()).balanceOf(address(steward)), 0, "steward holds underlying");
    assertEq(spoke.balanceOf(address(steward)), 0, "steward holds shares");
    assertEq(IERC20(spoke.asset()).allowance(address(steward), address(spoke)), 0, "steward allowance left");
  }
}

contract Function_depositV3 is PoolExposureStewardTest {
  function test_revertsIf_notOwnerOrGuardian() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.depositV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_revertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
    steward.depositV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 0);
    vm.stopPrank();
  }

  function test_success() public {
    uint256 balanceBefore = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));
    vm.startPrank(guardian);

    steward.depositV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    assertGt(IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balanceBefore);
    vm.stopPrank();
  }
}

contract Function_migrateV2toV3 is PoolExposureStewardTest {
  function test_revertsIf_notOwnerOrGuardian() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.migrateV2toV3(
      address(AaveV2Ethereum.POOL), address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6
    );
    vm.stopPrank();
  }

  function test_revertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
    steward.migrateV2toV3(
      address(AaveV2Ethereum.POOL), address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 0
    );
    vm.stopPrank();
  }

  function test_revertsIf_invalidV2Pool() public {
    vm.startPrank(guardian);

    vm.expectRevert(IPoolExposureSteward.UnrecognizedPool.selector);
    steward.migrateV2toV3(
      makeAddr("fake-pool"), address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6
    );
  }

  function test_revertsIf_invalidV3Pool() public {
    vm.startPrank(guardian);

    vm.expectRevert(IPoolExposureSteward.UnrecognizedPool.selector);
    steward.migrateV2toV3(
      address(AaveV2Ethereum.POOL), makeAddr("fake-pool"), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6
    );
  }

  function test_success() public {
    uint256 balanceV2Before = IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 balanceV3Before = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.startPrank(guardian);

    steward.migrateV2toV3(
      address(AaveV2Ethereum.POOL), address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6
    );

    assertLt(IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balanceV2Before);
    assertGt(IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balanceV3Before);
    vm.stopPrank();
  }
}

contract Function_migrateBetweenV3 is PoolExposureStewardTest {
  function test_revertsIf_notOwnerOrGuardian() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.migrateBetweenV3(
      address(AaveV3Ethereum.POOL), address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6
    );
    vm.stopPrank();
  }

  function test_revertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
    steward.migrateBetweenV3(
      address(AaveV3Ethereum.POOL), address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 0
    );
    vm.stopPrank();
  }

  function test_success() public {
    uint256 balanceBefore = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 balanceBeforeEtherFi =
      IERC20(AaveV3EthereumEtherFiAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    // The EtherFi USDC supply cap is reached at the fork block
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    AaveV3EthereumEtherFi.POOL_CONFIGURATOR.setSupplyCap(AaveV3EthereumEtherFiAssets.USDC_UNDERLYING, 0);

    vm.prank(guardian);
    steward.migrateBetweenV3(
      address(AaveV3Ethereum.POOL), address(AaveV3EthereumEtherFi.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6
    );

    assertApproxEqAbs(
      IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balanceBefore - 1_000e6, 1
    );
    assertApproxEqAbs(
      IERC20(AaveV3EthereumEtherFiAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)),
      balanceBeforeEtherFi + 1_000e6,
      1
    );
  }
}

contract Function_withdrawV3 is PoolExposureStewardTest {
  function test_revertsIf_notOwnerOrGuardian() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.withdrawV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_revertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
    steward.withdrawV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 0);
    vm.stopPrank();
  }

  function test_success() public {
    uint256 balanceV3Before = IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.startPrank(guardian);
    steward.withdrawV3(address(AaveV3Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);

    assertLt(IERC20(AaveV3EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balanceV3Before);
    vm.stopPrank();
  }
}

contract Function_withdrawV2 is PoolExposureStewardTest {
  function test_revertsIf_notOwnerOrGuardian() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.withdrawV2(address(AaveV2Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 1_000e6);
    vm.stopPrank();
  }

  function test_revertsIf_zeroAmount() public {
    vm.startPrank(guardian);

    vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
    steward.withdrawV2(address(AaveV2Ethereum.POOL), AaveV3EthereumAssets.USDC_UNDERLYING, 0);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(guardian);

    uint256 balanceV2Before = IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.startPrank(guardian);
    steward.withdrawV2(address(AaveV2Ethereum.POOL), AaveV2EthereumAssets.USDC_UNDERLYING, 1_0_000e6);

    assertLt(IERC20(AaveV2EthereumAssets.USDC_A_TOKEN).balanceOf(address(AaveV3Ethereum.COLLECTOR)), balanceV2Before);
    vm.stopPrank();
  }
}

contract Function_approvePool is PoolExposureStewardTest {
  function test_revertsIf_notOwner() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.approvePool(address(AaveV3Ethereum.POOL), true);
    vm.stopPrank();
  }

  function test_revertsIf_invalidZeroAddress() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    vm.expectRevert(IPoolExposureSteward.InvalidZeroAddress.selector);
    steward.approvePool(address(0), true);
    vm.stopPrank();
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ApprovedV3Pool(address(50));
    steward.approvePool(address(50), true);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ApprovedV2Pool(address(51));
    steward.approvePool(address(51), false);
    vm.stopPrank();
  }
}

contract Function_revokePool is PoolExposureStewardTest {
  function test_revertsIf_notOwner() public {
    vm.startPrank(alice);

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.revokePool(address(AaveV3Ethereum.POOL), true);
    vm.stopPrank();
  }

  function test_revertsIf_invalidZeroAddress() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    vm.expectRevert(IPoolExposureSteward.UnrecognizedPool.selector);
    steward.revokePool(address(0), true);
    vm.stopPrank();
  }

  function test_revertsIf_unrecognizedV2Pool() public {
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectRevert(IPoolExposureSteward.UnrecognizedPool.selector);
    steward.revokePool(makeAddr("fake-pool"), false);
  }

  function test_success() public {
    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);

    vm.expectEmit(true, true, true, true, address(steward));
    emit RevokedV3Pool(address(AaveV3Ethereum.POOL));
    steward.revokePool(address(AaveV3Ethereum.POOL), true);

    vm.expectEmit(true, true, true, true, address(steward));
    emit RevokedV2Pool(address(AaveV2Ethereum.POOL));
    steward.revokePool(address(AaveV2Ethereum.POOL), false);
    vm.stopPrank();
  }
}

contract Function_emergencyTokenTransfer is PoolExposureStewardTest {
  function test_successful_permissionless() public {
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);

    uint256 aaveAmount = 1_000e18;

    deal(AaveV2EthereumAssets.AAVE_UNDERLYING, address(steward), aaveAmount);

    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), aaveAmount);

    uint256 initialCollectorAaveBalance =
      IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR));

    steward.rescueToken(AaveV2EthereumAssets.AAVE_UNDERLYING);

    assertEq(
      IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR)),
      initialCollectorAaveBalance + aaveAmount
    );
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);
  }

  function test_successful_governanceCaller() public {
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);

    uint256 aaveAmount = 1_000e18;

    deal(AaveV2EthereumAssets.AAVE_UNDERLYING, address(steward), aaveAmount);

    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), aaveAmount);

    uint256 initialCollectorAaveBalance =
      IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR));

    vm.startPrank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.rescueToken(AaveV2EthereumAssets.AAVE_UNDERLYING);
    vm.stopPrank();

    assertEq(
      IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(AaveV2Ethereum.COLLECTOR)),
      initialCollectorAaveBalance + aaveAmount
    );
    assertEq(IERC20(AaveV2EthereumAssets.AAVE_UNDERLYING).balanceOf(address(steward)), 0);
  }

  function test_rescueEth() public {
    uint256 mintAmount = 1_000_000e18;
    deal(address(steward), mintAmount);

    uint256 collectorBalanceBefore = address(AaveV2Ethereum.COLLECTOR).balance;

    steward.rescueEth();

    uint256 collectorBalanceAfter = address(AaveV2Ethereum.COLLECTOR).balance;

    assertEq(collectorBalanceAfter - collectorBalanceBefore, mintAmount);
    assertEq(address(steward).balance, 0);
  }
}

contract Function_maxRescue is PoolExposureStewardTest {
  function test_maxRescue() public {
    assertEq(steward.maxRescue(AaveV3EthereumAssets.USDC_UNDERLYING), 0);

    uint256 mintAmount = 1_000_000e18;
    deal(AaveV3EthereumAssets.USDC_UNDERLYING, address(steward), mintAmount);

    assertEq(steward.maxRescue(AaveV3EthereumAssets.USDC_UNDERLYING), mintAmount);
  }
}

contract Function_depositV4 is PoolExposureStewardTest {
  function test_revertsIf_notOwnerOrGuardian() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.depositV4(address(USDC_SPOKE), 1_000e6);
  }

  function test_revertsIf_unrecognizedTokenizationSpoke() public {
    vm.prank(guardian);
    vm.expectRevert(IPoolExposureSteward.UnrecognizedTokenizationSpoke.selector);
    steward.depositV4(address(UNAPPROVED_SPOKE), 1e18);
  }

  function test_revertsIf_revokedTokenizationSpoke() public {
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.revokeTokenizationSpoke(address(USDC_SPOKE));

    vm.prank(guardian);
    vm.expectRevert(IPoolExposureSteward.UnrecognizedTokenizationSpoke.selector);
    steward.depositV4(address(USDC_SPOKE), 1_000e6);
  }

  function test_revertsIf_zeroAmount() public {
    vm.prank(guardian);
    vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
    steward.depositV4(address(USDC_SPOKE), 0);
  }

  function test_revertsIf_depositAllWithZeroCollectorBalance() public {
    deal(USDC_SPOKE.asset(), address(AaveV3Ethereum.COLLECTOR), 0);

    vm.prank(guardian);
    vm.expectRevert(IHub.InvalidAmount.selector);
    steward.depositV4(address(USDC_SPOKE), type(uint256).max);
  }

  function test_revertsIf_spokeHalted() public {
    _setSpokeHalted(USDC_SPOKE);

    vm.prank(guardian);
    vm.expectRevert(IHub.SpokeHalted.selector);
    steward.depositV4(address(USDC_SPOKE), 1_000e6);
  }

  function test_success_usdc() public {
    _testDeposit(USDC_SPOKE, 100_000e6);
  }

  function test_success_usdt() public {
    _testDeposit(USDT_SPOKE, 100_000e6);
  }

  function test_success_weth() public {
    _testDeposit(WETH_SPOKE, 100e18);
  }

  function test_success_gho() public {
    _testDeposit(GHO_SPOKE, 100_000e18);
  }

  function test_success_wbtc() public {
    _setAddCap(WBTC_SPOKE, 100);
    _testDeposit(WBTC_SPOKE, 1e8);
  }

  function test_success_depositAll() public {
    uint256 amount = 100_000e6;
    deal(USDC_SPOKE.asset(), address(AaveV3Ethereum.COLLECTOR), amount);
    uint256 expectedShares = USDC_SPOKE.previewDeposit(amount);
    uint256 sharesBefore = USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.prank(guardian);
    uint256 shares = steward.depositV4(address(USDC_SPOKE), type(uint256).max);

    assertEq(shares, expectedShares);
    assertEq(USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR)), sharesBefore + expectedShares);
    assertEq(IERC20(USDC_SPOKE.asset()).balanceOf(address(AaveV3Ethereum.COLLECTOR)), 0);
    _assertStewardUntouched(USDC_SPOKE);
  }

  /// @dev Deals more than `amount` so an exact deposit is distinguishable from a deposit-all
  function _testDeposit(ITokenizationSpoke spoke, uint256 amount) internal {
    IERC20 underlying = IERC20(spoke.asset());
    deal(address(underlying), address(AaveV3Ethereum.COLLECTOR), 2 * amount);
    uint256 expectedShares = spoke.previewDeposit(amount);
    uint256 sharesBefore = spoke.balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.prank(guardian);
    uint256 shares = steward.depositV4(address(spoke), amount);

    assertEq(shares, expectedShares);
    assertEq(spoke.balanceOf(address(AaveV3Ethereum.COLLECTOR)), sharesBefore + expectedShares);
    assertEq(underlying.balanceOf(address(AaveV3Ethereum.COLLECTOR)), amount);
    _assertStewardUntouched(spoke);
  }
}

contract Function_withdrawV4 is PoolExposureStewardTest {
  function test_revertsIf_notOwnerOrGuardian() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.withdrawV4(address(USDC_SPOKE), 1_000e6);
  }

  function test_revertsIf_unrecognizedTokenizationSpoke() public {
    vm.prank(guardian);
    vm.expectRevert(IPoolExposureSteward.UnrecognizedTokenizationSpoke.selector);
    steward.withdrawV4(address(UNAPPROVED_SPOKE), 1e18);
  }

  function test_revertsIf_zeroAmount() public {
    vm.prank(guardian);
    vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
    steward.withdrawV4(address(USDC_SPOKE), 0);
  }

  function test_revertsIf_amountAbovePosition() public {
    _depositToV4(USDC_SPOKE, 1_000e6);
    uint256 amount = 2_000e6;
    uint256 shares = USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 neededShares = USDC_SPOKE.previewWithdraw(amount);

    vm.prank(guardian);
    vm.expectRevert(
      abi.encodeWithSelector(
        IERC20Errors.ERC20InsufficientBalance.selector, address(AaveV3Ethereum.COLLECTOR), shares, neededShares
      )
    );
    steward.withdrawV4(address(USDC_SPOKE), amount);
  }

  /// @dev maxWithdraw is 0 on a halted spoke, so withdraw-all reaches the Hub with a zero amount
  function test_revertsIf_withdrawAllOnHaltedSpoke() public {
    _depositToV4(USDC_SPOKE, 1_000e6);
    _setSpokeHalted(USDC_SPOKE);

    vm.prank(guardian);
    vm.expectRevert(IHub.InvalidAmount.selector);
    steward.withdrawV4(address(USDC_SPOKE), type(uint256).max);
  }

  function test_success_usdc() public {
    _testWithdraw(USDC_SPOKE, 100_000e6, 40_000e6);
  }

  function test_success_usdt() public {
    _testWithdraw(USDT_SPOKE, 100_000e6, 40_000e6);
  }

  function test_success_weth() public {
    _testWithdraw(WETH_SPOKE, 100e18, 40e18);
  }

  function test_success_gho() public {
    _testWithdraw(GHO_SPOKE, 100_000e18, 40_000e18);
  }

  function test_success_wbtc() public {
    _setAddCap(WBTC_SPOKE, 100);
    _testWithdraw(WBTC_SPOKE, 1e8, 4e7);
  }

  function test_success_withdrawAllIncludesInterest() public {
    _depositToV4(USDC_SPOKE, 100_000e6);
    uint256 maxWithdrawBefore = USDC_SPOKE.maxWithdraw(address(AaveV3Ethereum.COLLECTOR));
    skip(30 days);
    uint256 maxWithdrawAfter = USDC_SPOKE.maxWithdraw(address(AaveV3Ethereum.COLLECTOR));
    assertGt(maxWithdrawAfter, maxWithdrawBefore);

    vm.prank(guardian);
    uint256 withdrawn = steward.withdrawV4(address(USDC_SPOKE), type(uint256).max);

    assertEq(withdrawn, maxWithdrawAfter);
    assertEq(IERC20(USDC_SPOKE.asset()).balanceOf(address(AaveV3Ethereum.COLLECTOR)), maxWithdrawAfter);
    assertEq(USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR)), 0);
    _assertStewardUntouched(USDC_SPOKE);
  }

  function test_success_withdrawAllCappedByLiquidity() public {
    _depositToV4(USDC_SPOKE, 100_000e6);
    uint256 sharesBefore = USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 liquidity = 40_000e6;
    uint256 expectedShares = USDC_SPOKE.previewWithdraw(liquidity);
    vm.mockCall(
      USDC_SPOKE.hub(),
      abi.encodeWithSelector(IHubBase.getAssetLiquidity.selector, USDC_SPOKE.assetId()),
      abi.encode(liquidity)
    );

    vm.prank(guardian);
    uint256 withdrawn = steward.withdrawV4(address(USDC_SPOKE), type(uint256).max);

    assertEq(withdrawn, liquidity);
    assertEq(IERC20(USDC_SPOKE.asset()).balanceOf(address(AaveV3Ethereum.COLLECTOR)), liquidity);
    assertEq(USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR)), sharesBefore - expectedShares);
    _assertStewardUntouched(USDC_SPOKE);
  }

  function _testWithdraw(ITokenizationSpoke spoke, uint256 depositAmount, uint256 withdrawAmount) internal {
    IERC20 underlying = IERC20(spoke.asset());
    _depositToV4(spoke, depositAmount);
    skip(30 days);
    uint256 sharesBefore = spoke.balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 underlyingBefore = underlying.balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 expectedShares = spoke.previewWithdraw(withdrawAmount);

    vm.prank(guardian);
    uint256 withdrawn = steward.withdrawV4(address(spoke), withdrawAmount);

    assertEq(withdrawn, withdrawAmount);
    assertEq(underlying.balanceOf(address(AaveV3Ethereum.COLLECTOR)), underlyingBefore + withdrawAmount);
    assertEq(spoke.balanceOf(address(AaveV3Ethereum.COLLECTOR)), sharesBefore - expectedShares);
    _assertStewardUntouched(spoke);
  }
}

contract Function_migrateV2toV4 is PoolExposureStewardTest {
  function test_revertsIf_notOwnerOrGuardian() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.migrateV2toV4(address(AaveV2Ethereum.POOL), address(USDC_SPOKE), 1_000e6);
  }

  function test_revertsIf_unrecognizedV2Pool() public {
    vm.prank(guardian);
    vm.expectRevert(IPoolExposureSteward.UnrecognizedPool.selector);
    steward.migrateV2toV4(makeAddr("fake-pool"), address(USDC_SPOKE), 1_000e6);
  }

  function test_revertsIf_unrecognizedTokenizationSpoke() public {
    vm.prank(guardian);
    vm.expectRevert(IPoolExposureSteward.UnrecognizedTokenizationSpoke.selector);
    steward.migrateV2toV4(address(AaveV2Ethereum.POOL), address(UNAPPROVED_SPOKE), 1e18);
  }

  function test_revertsIf_zeroAmount() public {
    vm.prank(guardian);
    vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
    steward.migrateV2toV4(address(AaveV2Ethereum.POOL), address(USDC_SPOKE), 0);
  }

  function test_success() public {
    _accrueV2Treasury();
    uint256 amount = 10_000e6;
    IERC20 aToken = IERC20(AaveV2EthereumAssets.USDC_A_TOKEN);
    uint256 aTokenBefore = aToken.balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 underlyingBefore = IERC20(USDC_SPOKE.asset()).balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 sharesBefore = USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 expectedShares = USDC_SPOKE.previewDeposit(amount);

    vm.prank(guardian);
    uint256 shares = steward.migrateV2toV4(address(AaveV2Ethereum.POOL), address(USDC_SPOKE), amount);

    assertEq(shares, expectedShares);
    assertApproxEqAbs(aToken.balanceOf(address(AaveV3Ethereum.COLLECTOR)), aTokenBefore - amount, 2);
    assertEq(USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR)), sharesBefore + expectedShares);
    assertEq(IERC20(USDC_SPOKE.asset()).balanceOf(address(AaveV3Ethereum.COLLECTOR)), underlyingBefore);
    _assertStewardUntouched(USDC_SPOKE);
  }

  function test_success_migrateAll() public {
    _accrueV2Treasury();
    IERC20 aToken = IERC20(AaveV2EthereumAssets.USDC_A_TOKEN);
    uint256 aTokenBefore = aToken.balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 underlyingBefore = IERC20(USDC_SPOKE.asset()).balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 sharesBefore = USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR));

    vm.prank(guardian);
    uint256 shares = steward.migrateV2toV4(address(AaveV2Ethereum.POOL), address(USDC_SPOKE), type(uint256).max);

    assertEq(aToken.balanceOf(address(AaveV3Ethereum.COLLECTOR)), 0);
    assertEq(USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR)), sharesBefore + shares);
    assertApproxEqAbs(USDC_SPOKE.convertToAssets(shares), aTokenBefore, 2);
    assertEq(IERC20(USDC_SPOKE.asset()).balanceOf(address(AaveV3Ethereum.COLLECTOR)), underlyingBefore);
    _assertStewardUntouched(USDC_SPOKE);
  }
}

contract Function_migrateV3toV4 is PoolExposureStewardTest {
  function test_revertsIf_notOwnerOrGuardian() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.migrateV3toV4(address(AaveV3Ethereum.POOL), address(USDC_SPOKE), 1_000e6);
  }

  function test_revertsIf_unrecognizedV3Pool() public {
    vm.prank(guardian);
    vm.expectRevert(IPoolExposureSteward.UnrecognizedPool.selector);
    steward.migrateV3toV4(makeAddr("fake-pool"), address(USDC_SPOKE), 1_000e6);
  }

  function test_revertsIf_unrecognizedTokenizationSpoke() public {
    vm.prank(guardian);
    vm.expectRevert(IPoolExposureSteward.UnrecognizedTokenizationSpoke.selector);
    steward.migrateV3toV4(address(AaveV3Ethereum.POOL), address(UNAPPROVED_SPOKE), 1e18);
  }

  function test_revertsIf_zeroAmount() public {
    vm.prank(guardian);
    vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
    steward.migrateV3toV4(address(AaveV3Ethereum.POOL), address(USDC_SPOKE), 0);
  }

  function test_success_usdc() public {
    _testMigrate(USDC_SPOKE, AaveV3EthereumAssets.USDC_A_TOKEN, 100_000e6);
  }

  function test_success_usdt() public {
    _testMigrate(USDT_SPOKE, AaveV3EthereumAssets.USDT_A_TOKEN, 100_000e6);
  }

  function test_success_weth() public {
    _testMigrate(WETH_SPOKE, AaveV3EthereumAssets.WETH_A_TOKEN, 10e18);
  }

  function test_success_migrateAll() public {
    IERC20 aToken = IERC20(AaveV3EthereumAssets.USDT_A_TOKEN);
    uint256 aTokenBefore = aToken.balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 underlyingBefore = IERC20(USDT_SPOKE.asset()).balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 sharesBefore = USDT_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR));
    _setAddCap(USDT_SPOKE, USDT_SPOKE.MAX_ALLOWED_SPOKE_CAP());

    vm.prank(guardian);
    uint256 shares = steward.migrateV3toV4(address(AaveV3Ethereum.POOL), address(USDT_SPOKE), type(uint256).max);

    assertEq(aToken.balanceOf(address(AaveV3Ethereum.COLLECTOR)), 0);
    assertEq(USDT_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR)), sharesBefore + shares);
    assertApproxEqAbs(USDT_SPOKE.convertToAssets(shares), aTokenBefore, 2);
    assertEq(IERC20(USDT_SPOKE.asset()).balanceOf(address(AaveV3Ethereum.COLLECTOR)), underlyingBefore);
    _assertStewardUntouched(USDT_SPOKE);
  }

  function _testMigrate(ITokenizationSpoke spoke, address aTokenAddress, uint256 amount) internal {
    IERC20 aToken = IERC20(aTokenAddress);
    uint256 aTokenBefore = aToken.balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 underlyingBefore = IERC20(spoke.asset()).balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 sharesBefore = spoke.balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 expectedShares = spoke.previewDeposit(amount);

    vm.prank(guardian);
    uint256 shares = steward.migrateV3toV4(address(AaveV3Ethereum.POOL), address(spoke), amount);

    assertEq(shares, expectedShares);
    assertApproxEqAbs(aToken.balanceOf(address(AaveV3Ethereum.COLLECTOR)), aTokenBefore - amount, 2);
    assertEq(spoke.balanceOf(address(AaveV3Ethereum.COLLECTOR)), sharesBefore + expectedShares);
    assertEq(IERC20(spoke.asset()).balanceOf(address(AaveV3Ethereum.COLLECTOR)), underlyingBefore);
    _assertStewardUntouched(spoke);
  }
}

contract Function_migrateBetweenV4 is PoolExposureStewardTest {
  // The only CORE spoke per asset means a successful V4 to V4 migration needs a spoke from another hub
  ITokenizationSpoke public constant PRIME_USDC_SPOKE = AaveV4EthereumTokenizationSpokes.PRIME_USDC_TOKENIZATION_SPOKE;

  function test_revertsIf_notOwnerOrGuardian() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.migrateBetweenV4({
      fromTokenizationSpoke: address(USDC_SPOKE), toTokenizationSpoke: address(PRIME_USDC_SPOKE), amount: 1_000e6
    });
  }

  function test_revertsIf_unrecognizedFromTokenizationSpoke() public {
    vm.prank(guardian);
    vm.expectRevert(IPoolExposureSteward.UnrecognizedTokenizationSpoke.selector);
    steward.migrateBetweenV4({
      fromTokenizationSpoke: address(PRIME_USDC_SPOKE), toTokenizationSpoke: address(USDC_SPOKE), amount: 1_000e6
    });
  }

  function test_revertsIf_unrecognizedToTokenizationSpoke() public {
    vm.prank(guardian);
    vm.expectRevert(IPoolExposureSteward.UnrecognizedTokenizationSpoke.selector);
    steward.migrateBetweenV4({
      fromTokenizationSpoke: address(USDC_SPOKE), toTokenizationSpoke: address(PRIME_USDC_SPOKE), amount: 1_000e6
    });
  }

  function test_revertsIf_mismatchingAssets() public {
    vm.prank(guardian);
    vm.expectRevert(IPoolExposureSteward.MismatchingTokenizationSpokeAssets.selector);
    steward.migrateBetweenV4({
      fromTokenizationSpoke: address(USDC_SPOKE), toTokenizationSpoke: address(USDT_SPOKE), amount: 1_000e6
    });
  }

  function test_revertsIf_zeroAmount() public {
    _approvePrimeUsdc();

    vm.prank(guardian);
    vm.expectRevert(CollectorUtils.InvalidZeroAmount.selector);
    steward.migrateBetweenV4({
      fromTokenizationSpoke: address(USDC_SPOKE), toTokenizationSpoke: address(PRIME_USDC_SPOKE), amount: 0
    });
  }

  function test_success() public {
    _approvePrimeUsdc();
    _depositToV4(USDC_SPOKE, 100_000e6);
    uint256 amount = 40_000e6;
    uint256 fromSharesBefore = USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 toSharesBefore = PRIME_USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 underlyingBefore = IERC20(USDC_SPOKE.asset()).balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 expectedFromShares = USDC_SPOKE.previewWithdraw(amount);
    uint256 expectedToShares = PRIME_USDC_SPOKE.previewDeposit(amount);

    vm.prank(guardian);
    uint256 shares = steward.migrateBetweenV4({
      fromTokenizationSpoke: address(USDC_SPOKE), toTokenizationSpoke: address(PRIME_USDC_SPOKE), amount: amount
    });

    assertEq(shares, expectedToShares);
    assertEq(USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR)), fromSharesBefore - expectedFromShares);
    assertEq(PRIME_USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR)), toSharesBefore + expectedToShares);
    assertEq(IERC20(USDC_SPOKE.asset()).balanceOf(address(AaveV3Ethereum.COLLECTOR)), underlyingBefore);
    _assertStewardUntouched(USDC_SPOKE);
    _assertStewardUntouched(PRIME_USDC_SPOKE);
  }

  function test_success_migrateAll() public {
    _approvePrimeUsdc();
    _depositToV4(USDC_SPOKE, 100_000e6);
    skip(30 days);
    uint256 maxWithdraw = USDC_SPOKE.maxWithdraw(address(AaveV3Ethereum.COLLECTOR));
    uint256 toSharesBefore = PRIME_USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 expectedToShares = PRIME_USDC_SPOKE.previewDeposit(maxWithdraw);

    vm.prank(guardian);
    uint256 shares = steward.migrateBetweenV4({
      fromTokenizationSpoke: address(USDC_SPOKE),
      toTokenizationSpoke: address(PRIME_USDC_SPOKE),
      amount: type(uint256).max
    });

    assertEq(shares, expectedToShares);
    assertEq(USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR)), 0);
    assertEq(PRIME_USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR)), toSharesBefore + expectedToShares);
    _assertStewardUntouched(USDC_SPOKE);
    _assertStewardUntouched(PRIME_USDC_SPOKE);
  }

  /// @dev Approves the PRIME USDC spoke and lifts its add cap, which is close to full at the fork block
  function _approvePrimeUsdc() internal {
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    steward.approveTokenizationSpoke(address(PRIME_USDC_SPOKE));
    _setAddCap(PRIME_USDC_SPOKE, PRIME_USDC_SPOKE.MAX_ALLOWED_SPOKE_CAP());
  }
}

contract Function_approveTokenizationSpoke is PoolExposureStewardTest {
  function test_revertsIf_notOwner() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.approveTokenizationSpoke(address(UNAPPROVED_SPOKE));
  }

  function test_revertsIf_guardian() public {
    vm.prank(guardian);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, guardian));
    steward.approveTokenizationSpoke(address(UNAPPROVED_SPOKE));
  }

  function test_revertsIf_invalidZeroAddress() public {
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectRevert(IPoolExposureSteward.InvalidZeroAddress.selector);
    steward.approveTokenizationSpoke(address(0));
  }

  function test_constructorApprovals() public view {
    assertTrue(steward.approvedTokenizationSpokes(address(USDC_SPOKE)));
    assertTrue(steward.approvedTokenizationSpokes(address(USDT_SPOKE)));
    assertTrue(steward.approvedTokenizationSpokes(address(WETH_SPOKE)));
    assertTrue(steward.approvedTokenizationSpokes(address(GHO_SPOKE)));
    assertTrue(steward.approvedTokenizationSpokes(address(WBTC_SPOKE)));
    assertFalse(steward.approvedTokenizationSpokes(address(UNAPPROVED_SPOKE)));
  }

  function test_success() public {
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectEmit(true, true, true, true, address(steward));
    emit ApprovedTokenizationSpoke(address(UNAPPROVED_SPOKE));
    steward.approveTokenizationSpoke(address(UNAPPROVED_SPOKE));

    assertTrue(steward.approvedTokenizationSpokes(address(UNAPPROVED_SPOKE)));
  }
}

contract Function_revokeTokenizationSpoke is PoolExposureStewardTest {
  function test_revertsIf_notOwner() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.revokeTokenizationSpoke(address(USDC_SPOKE));
  }

  function test_revertsIf_unrecognizedTokenizationSpoke() public {
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectRevert(IPoolExposureSteward.UnrecognizedTokenizationSpoke.selector);
    steward.revokeTokenizationSpoke(address(UNAPPROVED_SPOKE));
  }

  function test_success() public {
    vm.prank(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    vm.expectEmit(true, true, true, true, address(steward));
    emit RevokedTokenizationSpoke(address(USDC_SPOKE));
    steward.revokeTokenizationSpoke(address(USDC_SPOKE));

    assertFalse(steward.approvedTokenizationSpokes(address(USDC_SPOKE)));
  }
}

contract Function_multicallV4 is PoolExposureStewardTest {
  function test_success_migrateV3toV4AndWithdrawV4() public {
    uint256 migrateAmount = 100_000e6;
    uint256 withdrawAmount = 40_000e6;
    uint256 underlyingBefore = IERC20(USDC_SPOKE.asset()).balanceOf(address(AaveV3Ethereum.COLLECTOR));
    uint256 sharesBefore = USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR));

    bytes[] memory calls = new bytes[](2);
    calls[0] = abi.encodeCall(
      IPoolExposureSteward.migrateV3toV4, (address(AaveV3Ethereum.POOL), address(USDC_SPOKE), migrateAmount)
    );
    calls[1] = abi.encodeCall(IPoolExposureSteward.withdrawV4, (address(USDC_SPOKE), withdrawAmount));

    vm.prank(guardian);
    bytes[] memory results = steward.multicall(calls);

    uint256 mintedShares = abi.decode(results[0], (uint256));
    uint256 withdrawn = abi.decode(results[1], (uint256));
    assertEq(withdrawn, withdrawAmount);
    assertEq(IERC20(USDC_SPOKE.asset()).balanceOf(address(AaveV3Ethereum.COLLECTOR)), underlyingBefore + withdrawAmount);
    assertApproxEqAbs(
      USDC_SPOKE.convertToAssets(USDC_SPOKE.balanceOf(address(AaveV3Ethereum.COLLECTOR)) - sharesBefore),
      migrateAmount - withdrawAmount,
      2
    );
    assertGt(mintedShares, 0);
    _assertStewardUntouched(USDC_SPOKE);
  }
}
