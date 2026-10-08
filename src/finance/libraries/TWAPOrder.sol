// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;
// Vendored from https://github.com/cowprotocol/composable-cow/blob/c0435953ac8312a606d66c91554f2bb4d22ec686/src/types/twap/libraries/TWAPOrder.sol
// composable-cow tag ack3-rev2.0 (file last changed in 24d556b634e21065e0ee70dd27469a6e699a8998).
// Local changes: import paths; `orderFor` and its imports removed, the steward only validates.

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IConditionalOrder} from "src/finance/interfaces/IConditionalOrder.sol";

// --- error strings

string constant INVALID_SAME_TOKEN = "same token";
string constant INVALID_TOKEN = "invalid token";
string constant INVALID_PART_SELL_AMOUNT = "invalid part sell amount";
string constant INVALID_MIN_PART_LIMIT = "invalid min part limit";
string constant INVALID_START_TIME = "invalid start time";
string constant INVALID_NUM_PARTS = "invalid num parts";
string constant INVALID_FREQUENCY = "invalid frequency";
string constant INVALID_SPAN = "invalid span";

/**
 * @title Time-weighted Average Order Library
 * @author mfw78 <mfw78@rndlabs.xyz>
 * @dev Structs, errors, and functions for time-weighted average orders.
 */
library TWAPOrder {
  // --- structs

  struct Data {
    IERC20 sellToken;
    IERC20 buyToken;
    address receiver;
    uint256 partSellAmount; // amount of sellToken to sell in each part
    uint256 minPartLimit; // max price to pay for a unit of buyToken denominated in sellToken
    uint256 t0;
    uint256 n;
    uint256 t;
    uint256 span;
    bytes32 appData;
  }

  // --- functions

  /**
   * @dev revert if the order is invalid
   * @param self The TWAP order to validate
   */
  function validate(Data memory self) internal pure {
    if (!(self.sellToken != self.buyToken)) revert IConditionalOrder.OrderNotValid(INVALID_SAME_TOKEN);
    if (!(address(self.sellToken) != address(0) && address(self.buyToken) != address(0))) {
      revert IConditionalOrder.OrderNotValid(INVALID_TOKEN);
    }
    if (!(self.partSellAmount > 0)) revert IConditionalOrder.OrderNotValid(INVALID_PART_SELL_AMOUNT);
    if (!(self.minPartLimit > 0)) revert IConditionalOrder.OrderNotValid(INVALID_MIN_PART_LIMIT);
    if (!(self.t0 < type(uint32).max)) revert IConditionalOrder.OrderNotValid(INVALID_START_TIME);
    if (!(self.n > 1 && self.n <= type(uint32).max)) revert IConditionalOrder.OrderNotValid(INVALID_NUM_PARTS);
    if (!(self.t > 0 && self.t <= 365 days)) revert IConditionalOrder.OrderNotValid(INVALID_FREQUENCY);
    if (!(self.span <= self.t)) revert IConditionalOrder.OrderNotValid(INVALID_SPAN);
  }
}
