// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardRescueTokenTest is SwapStewardTestBase {
  uint256 internal constant RESCUE_BALANCE = 1_000e18;
  uint256 internal constant RESCUE_PARTIAL = 500e18;

  function test_rescueToken_revertsWith_OnlyGuardianOrOwnerInvalidCaller_fullBalance() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.rescueToken(otherToken);
  }

  function test_rescueToken_revertsWith_OnlyGuardianOrOwnerInvalidCaller_amount() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    steward.rescueToken(otherToken, 1);
  }

  function test_rescueToken() public {
    deal(otherToken, address(steward), RESCUE_BALANCE);

    vm.prank(guardian);
    steward.rescueToken(otherToken);

    assertEq(IERC20(otherToken).balanceOf(address(steward)), 0);
    assertEq(IERC20(otherToken).balanceOf(collector), RESCUE_BALANCE);
  }

  function test_rescueToken_amount() public {
    deal(otherToken, address(steward), RESCUE_BALANCE);

    vm.prank(guardian);
    steward.rescueToken(otherToken, RESCUE_PARTIAL);

    assertEq(IERC20(otherToken).balanceOf(address(steward)), RESCUE_BALANCE - RESCUE_PARTIAL);
    assertEq(IERC20(otherToken).balanceOf(collector), RESCUE_PARTIAL);
  }
}
