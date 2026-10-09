// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {AggregatorInterface} from "aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {MockAggregator} from "tests/finance/swap/OracleMocks.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardSetTokenOracleTest is SwapStewardTestBase {
  function test_setTokenOracle_revertsWith_OwnableUnauthorizedAccount() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    steward.setTokenOracle(fromToken, fromOracle);
  }

  function test_setTokenOracle_revertsWith_InvalidZeroAddress() public {
    vm.prank(executor);
    vm.expectRevert(ISwapSteward.InvalidZeroAddress.selector);
    steward.setTokenOracle(fromToken, address(0));
  }

  function test_setTokenOracle_revertsWith_PriceFeedIncompatibleDecimals() public {
    vm.mockCall(fromOracle, abi.encodeWithSelector(AggregatorInterface.decimals.selector), abi.encode(18));

    vm.prank(executor);
    vm.expectRevert(ISwapSteward.PriceFeedIncompatibleDecimals.selector);
    steward.setTokenOracle(fromToken, fromOracle);
  }

  function test_setTokenOracle_revertsWith_PriceFeedInvalidAnswer_zero() public {
    address mockOracle = address(new MockAggregator(0));

    vm.prank(executor);
    vm.expectRevert(ISwapSteward.PriceFeedInvalidAnswer.selector);
    steward.setTokenOracle(fromToken, mockOracle);
  }

  function test_setTokenOracle_revertsWith_PriceFeedInvalidAnswer_negative() public {
    address mockOracle = address(new MockAggregator(-1));

    vm.prank(executor);
    vm.expectRevert(ISwapSteward.PriceFeedInvalidAnswer.selector);
    steward.setTokenOracle(fromToken, mockOracle);
  }

  function test_setTokenOracle() public {
    assertEq(steward.priceOracle(otherToken), address(0));
    assertEq(steward.priceOracle(fromToken), fromOracle);

    vm.startPrank(executor);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.SetTokenOracle(otherToken, otherOracle);
    steward.setTokenOracle(otherToken, otherOracle);
    assertEq(steward.priceOracle(otherToken), otherOracle);

    vm.expectEmit(true, true, true, true, address(steward));
    emit ISwapSteward.SetTokenOracle(fromToken, toOracle);
    steward.setTokenOracle(fromToken, toOracle);
    assertEq(steward.priceOracle(fromToken), toOracle);
    vm.stopPrank();
  }
}
