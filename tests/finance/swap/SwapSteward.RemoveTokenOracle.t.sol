// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardRemoveTokenOracleTest is SwapStewardTestBase {
  function test_removeTokenOracle_revertsWith_OwnableUnauthorizedAccount() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.removeTokenOracle(fromToken);
  }

  function test_removeTokenOracle_revertsWith_OracleNotSet() public {
    vm.prank(executor);
    vm.expectRevert(ISwapSteward.OracleNotSet.selector);
    steward.removeTokenOracle(otherToken);
  }

  function test_removeTokenOracle() public {
    assertEq(steward.priceOracle(fromToken), fromOracle);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.TokenOracleRemoved(fromToken);
    vm.prank(executor);
    steward.removeTokenOracle(fromToken);

    assertEq(steward.priceOracle(fromToken), address(0));
    assertEq(steward.priceOracle(toToken), toOracle);
  }

  function test_removeTokenOracle_setAfterRemove() public {
    vm.startPrank(executor);
    steward.removeTokenOracle(fromToken);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.SetTokenOracle(fromToken, toOracle);
    steward.setTokenOracle(fromToken, toOracle);
    vm.stopPrank();

    assertEq(steward.priceOracle(fromToken), toOracle);
  }

  function test_removeTokenOracle_keepsOpenOrder() public {
    address escrow = _swap(guardian, fromToken, toToken, swapAmount);
    uint32 validTo = uint32(block.timestamp + steward.ORDER_LIFETIME());

    vm.startPrank(executor);
    steward.removeTokenOracle(fromToken);
    steward.removeTokenOracle(toToken);
    vm.stopPrank();

    (GPv2Order.Data memory order,) = _getMarketOrderWithSignature(escrow, validTo);
    assertEq(address(order.sellToken), fromToken);
    assertEq(address(order.buyToken), toToken);
    assertEq(order.sellAmount, swapAmount);

    vm.prank(guardian);
    vm.expectRevert(ISwapSteward.OracleNotSet.selector);
    steward.swap(fromToken, toToken, swapAmount, SWAP_SLIPPAGE);
  }
}
