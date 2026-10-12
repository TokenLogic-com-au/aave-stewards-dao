// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardIncreaseGuardianTokenBudgetTest is SwapStewardTestBase {
  function test_increaseGuardianTokenBudget_revertsWith_OwnableUnauthorizedAccount() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.increaseGuardianTokenBudget(fromToken, 100 * swapAmount);
  }

  function test_increaseGuardianTokenBudget() public {
    uint256 amount = 100 * swapAmount;

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.UpdatedGuardianTokenBudget(fromToken, guardianBudget + amount);
    vm.prank(executor);
    steward.increaseGuardianTokenBudget(fromToken, amount);

    assertEq(steward.guardianTokenBudget(fromToken), guardianBudget + amount);
    assertEq(steward.guardianTokenBudget(toToken), 0);
  }
}
