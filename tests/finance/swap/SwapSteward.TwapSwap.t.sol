// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWithGuardian} from "solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol";
import {IConditionalOrder} from "src/finance/interfaces/IConditionalOrder.sol";
import {
  TWAPOrder,
  INVALID_TOKEN,
  INVALID_MIN_PART_LIMIT,
  INVALID_START_TIME,
  INVALID_NUM_PARTS,
  INVALID_FREQUENCY,
  INVALID_SPAN
} from "src/finance/libraries/TWAPOrder.sol";
import {ISwapSteward} from "src/finance/swap/interfaces/ISwapSteward.sol";
import {SwapStewardTestBase} from "tests/finance/swap/SwapSteward.Base.t.sol";

contract SwapStewardTwapSwapTest is SwapStewardTestBase {
  struct OrderBoundsCase {
    TWAPOrder.Data data;
    address caller;
    string invalidReason;
  }

  function test_twapSwap_revertsWith_OnlyGuardianOrOwnerInvalidCaller() public {
    TWAPOrder.Data memory data = _twapData(0, 0);

    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, alice));
    _twapSwap(alice, data);
  }

  function test_twapSwap_revertsWith_InvalidZeroAmount() public {
    TWAPOrder.Data memory data = _twapData(0, 0);
    data.partSellAmount = 0;

    vm.expectRevert(ISwapSteward.InvalidZeroAmount.selector);
    _twapSwap(guardian, data);
  }

  function test_twapSwap_revertsWith_UnrecognizedTokenSwap_pairNotApproved() public {
    TWAPOrder.Data memory data = _twapData(0, 0);
    data.buyToken = IERC20(otherToken);

    vm.expectRevert(ISwapSteward.UnrecognizedTokenSwap.selector);
    _twapSwap(guardian, data);
  }

  function test_twapSwap_revertsWith_InsufficientBudget() public {
    TWAPOrder.Data memory data = _twapData(0, 0);
    data.partSellAmount = guardianBudget / TWAP_NUM_PARTS + 1;

    vm.expectRevert(ISwapSteward.InsufficientBudget.selector);
    _twapSwap(guardian, data);
  }

  function test_twapSwap_revertsWith_StartTimeInPast() public {
    TWAPOrder.Data memory data = _twapData(block.timestamp - 1, 0);

    vm.expectRevert(ISwapSteward.StartTimeInPast.selector);
    _twapSwap(guardian, data);
  }

  function test_twapSwap_orderBounds() public {
    vm.prank(executor);
    steward.setSwappablePair(fromToken, address(0));
    deal(fromToken, collector, uint256(type(uint32).max) + 2 * twapPartAmount);

    OrderBoundsCase[] memory cases = new OrderBoundsCase[](10);
    for (uint256 i; i < cases.length; i++) {
      cases[i] = OrderBoundsCase({data: _twapData(block.timestamp, 0), caller: guardian, invalidReason: ""});
    }
    cases[0].data.t0 = type(uint32).max;
    cases[0].invalidReason = INVALID_START_TIME;
    cases[1].data.buyToken = IERC20(address(0));
    cases[1].invalidReason = INVALID_TOKEN;
    cases[2].data.minPartLimit = 0;
    cases[2].invalidReason = INVALID_MIN_PART_LIMIT;
    cases[3].data.n = 1;
    cases[3].invalidReason = INVALID_NUM_PARTS;
    cases[4].data.n = uint256(type(uint32).max) + 1;
    cases[4].invalidReason = INVALID_NUM_PARTS;
    cases[5].data.t = 0;
    cases[5].invalidReason = INVALID_FREQUENCY;
    cases[6].data.t = TWAP_MAX_PART_DURATION + 1;
    cases[6].invalidReason = INVALID_FREQUENCY;
    cases[7].data.span = TWAP_PART_DURATION + 1;
    cases[7].invalidReason = INVALID_SPAN;
    cases[8].data.n = 2;
    cases[8].data.t = TWAP_MAX_PART_DURATION;
    cases[8].data.span = TWAP_MAX_PART_DURATION;
    cases[9].data.partSellAmount = 1;
    cases[9].data.n = type(uint32).max;
    cases[9].caller = executor;

    for (uint256 i; i < cases.length; i++) {
      OrderBoundsCase memory c = cases[i];
      if (bytes(c.invalidReason).length != 0) {
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, c.invalidReason));
        _twapSwap(c.caller, c.data);
      } else {
        address escrow = _twapSwap(c.caller, c.data);
        (, bytes32 orderHash) = steward.swaps(escrow);
        assertEq(orderHash, keccak256(abi.encode(_twapParams(c.data))));
        assertEq(IERC20(fromToken).balanceOf(escrow), c.data.partSellAmount * c.data.n);
      }
    }
  }

  function test_twapSwap_startTimeZero() public {
    uint256 t0 = block.timestamp;

    address escrow = _twapSwap(guardian, _twapData(0, 0));

    (, bytes32 orderHash) = steward.swaps(escrow);
    assertEq(orderHash, keccak256(abi.encode(_twapParams(_twapData(t0, 0)))));
  }

  function test_twapSwap_startTimeNow() public {
    uint256 t0 = block.timestamp;

    address escrow = _twapSwap(guardian, _twapData(t0, 0));

    (, bytes32 orderHash) = steward.swaps(escrow);
    assertEq(orderHash, keccak256(abi.encode(_twapParams(_twapData(t0, 0)))));
  }

  function test_twapSwap_ownerSkipsBudget() public {
    TWAPOrder.Data memory data = _twapData(0, 0);
    data.partSellAmount = guardianBudget / TWAP_NUM_PARTS + swapAmount / 10;
    uint256 total = data.partSellAmount * TWAP_NUM_PARTS;
    assertGt(total, guardianBudget);

    address escrow = _twapSwap(executor, data);

    assertEq(steward.guardianTokenBudget(fromToken), guardianBudget);
    assertEq(IERC20(fromToken).balanceOf(escrow), total);
  }
}
