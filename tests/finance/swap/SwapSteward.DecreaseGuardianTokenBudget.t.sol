// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardDecreaseGuardianTokenBudgetTest is SwapStewardTestBase {
  function test_decreaseGuardianTokenBudget_revertsWith_OwnableUnauthorizedAccount() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.decreaseGuardianTokenBudget(fromToken, swapAmount);
  }

  function test_decreaseGuardianTokenBudget_revertsWith_InsufficientBudget() public {
    vm.prank(executor);
    vm.expectRevert(ISwapSteward.InsufficientBudget.selector);
    steward.decreaseGuardianTokenBudget(fromToken, guardianBudget + 1);
  }

  function test_decreaseGuardianTokenBudget() public {
    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.UpdatedGuardianTokenBudget(fromToken, guardianBudget - swapAmount);
    vm.prank(executor);
    steward.decreaseGuardianTokenBudget(fromToken, swapAmount);

    assertEq(steward.guardianTokenBudget(fromToken), guardianBudget - swapAmount);
  }
}
