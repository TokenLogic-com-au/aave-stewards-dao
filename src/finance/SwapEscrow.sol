// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {ERC1271Forwarder} from "src/finance/ERC1271Forwarder.sol";
import {IConditionalOrder} from "src/finance/interfaces/IConditionalOrder.sol";

/**
 * @title SwapEscrow
 * @author halaprix (Tokenlogic)
 * @notice Owner of one Composable CoW conditional order. SwapSteward deploys one minimal proxy clone
 * of this contract per swap, so the sell tokens and the relayer allowance of each order are separate.
 * @dev Clones have no storage. STEWARD, VAULT_RELAYER and COMPOSABLE_COW are immutables of the
 * implementation, which every clone reads through delegatecall.
 */
contract SwapEscrow is ERC1271Forwarder {
  using SafeERC20 for IERC20;

  /// @dev Caller is not the steward
  error OnlySteward();

  /// @notice Returns the SwapSteward that deployed the implementation and controls every clone
  address public immutable STEWARD;

  /// @notice Returns the GPv2VaultRelayer that pulls the sold tokens
  address public immutable VAULT_RELAYER;

  constructor(address composableCow, address vaultRelayer) ERC1271Forwarder(composableCow) {
    STEWARD = msg.sender;
    VAULT_RELAYER = vaultRelayer;
  }

  modifier onlySteward() {
    if (msg.sender != STEWARD) revert OnlySteward();
    _;
  }

  /// @notice Creates the conditional order and approves the relayer for the sell amount
  /// @param params Parameters of the conditional order
  /// @param token The token to sell
  /// @param amount The amount of token to sell
  function open(IConditionalOrder.ConditionalOrderParams calldata params, IERC20 token, uint256 amount)
    external
    onlySteward
  {
    COMPOSABLE_COW.create(params, true);
    token.forceApprove(VAULT_RELAYER, amount);
  }

  /// @notice Removes the conditional order, zeroes the relayer allowance and sends the token balance to `to`
  /// @param orderHash Hash of the conditional order on ComposableCoW
  /// @param token The token that was being sold
  /// @param to The receiver of the token balance
  /// @return The amount of token sent to `to`
  function close(bytes32 orderHash, IERC20 token, address to) external onlySteward returns (uint256) {
    COMPOSABLE_COW.remove(orderHash);
    token.forceApprove(VAULT_RELAYER, 0);

    uint256 balance = token.balanceOf(address(this));
    if (balance > 0) {
      token.safeTransfer(to, balance);
    }

    return balance;
  }
}
