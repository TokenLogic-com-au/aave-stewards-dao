// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GPv2Order} from "src/finance/libraries/GPv2Order.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardMainnetForkTestBase} from "tests/finance/swap/SwapStewardMainnetForkTestBase.sol";

contract SwapStewardRemoveTokenOracleForkTest is SwapStewardMainnetForkTestBase {
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
