// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardIncreaseTokenBudgetTest is SwapStewardTestBase {
  function test_increaseTokenBudget_revertsWith_OwnableUnauthorizedAccount() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.increaseTokenBudget(fromToken, 100 * swapAmount);
  }

  function test_increaseTokenBudget() public {
    uint256 amount = 100 * swapAmount;

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.UpdatedTokenBudget(fromToken, guardianBudget + amount);
    vm.prank(executor);
    steward.increaseTokenBudget(fromToken, amount);

    assertEq(steward.tokenBudget(fromToken), guardianBudget + amount);
    assertEq(steward.tokenBudget(toToken), 0);
  }
}
