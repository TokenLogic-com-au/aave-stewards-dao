// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardDecreaseTokenBudgetTest is SwapStewardTestBase {
  function test_decreaseTokenBudget_revertsWith_OwnableUnauthorizedAccount() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.decreaseTokenBudget(fromToken, swapAmount);
  }

  function test_decreaseTokenBudget_revertsWith_InsufficientBudget() public {
    vm.prank(executor);
    vm.expectRevert(ISwapSteward.InsufficientBudget.selector);
    steward.decreaseTokenBudget(fromToken, guardianBudget + 1);
  }

  function test_decreaseTokenBudget() public {
    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.UpdatedTokenBudget(fromToken, guardianBudget - swapAmount);
    vm.prank(executor);
    steward.decreaseTokenBudget(fromToken, swapAmount);

    assertEq(steward.tokenBudget(fromToken), guardianBudget - swapAmount);
  }
}
