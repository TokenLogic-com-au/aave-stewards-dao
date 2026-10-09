# Aave <> CoW Swap: MainnetSwapSteward

The MainnetSwapSteward is a smart contract tool developed in order to more easily allow the Aave DAO to swap its tokens.
Up until now, the DAO relied on custom one-use contracts in order to accomplish the swap of one token for another.
Some examples include the BAL <> AAVE swap from 2022, the acquisition of CRV or the acquisition of B-80BAL-20WETH.
All the instances listed above required significant time to develop, test, and review, all while reinventing the
wheel every time for something that should be easy to reuse.

MainnetSwapSteward facilitates swaps of tokens by the DAO without the constant need to review the contracts that do so.

## How It Works

The MainnetSwapSteward relies on [Milkman](https://github.com/cowdao-grants/milkman), a smart contract that builds on top of
[COW Swap](https://swap.cow.fi/#/faq/protocol), under the hood in order to find the best possible swap execution for
the DAO while protecting funds from MEV exploits and bad slippage.

MainnetSwapSteward is a permissioned smart contract, and it has two potential privileged users: the owner and the guardian.
The owner will be the DAO (however, ownership can be transferred) and the guardian is an address to be chosen by the
DAO to more easily swap/cancel swaps without relying on governance. MainnetSwapSteward can only withdraw tokens to the Collector contract.
The contract has a budget if functions are called by the guardian, which are set by the DAO. This prevents such a behavior as a looping where the DAO's
funds are drained because of paying slippage in an endless GHO -> USDC -> GHO loop (as an example).
Funds must be present in this contract in order for them to be executed.

### Methods

```
function swap(
    address milkman,
    address priceChecker,
    address fromToken,
    address toToken,
    address fromOracle,
    address toOracle,
    address recipient,
    uint256 amount,
    uint256 slippage
  ) external onlyOwnerOrGuardian
```

Swaps `fromToken` to `toToken` in the specified `amount`. The recipient of the `toToken` and sends the acquired funds to the recipient.

Slippage is specified in basis points, for example `100` is 1% slippage. The maximum amount would be `10_000` for 100% slippage.

A note on slippage and CoW Swap:

Slippage not only accounts for the difference in price, but also gas costs incurred for the swap itself. What follows is an example:
A user wants to swap 100 USDC for DAI, the price is about 1-to-1 as they are both stablecoins. The slippage needed for this trade, with
gas prices of 80 gwei could be over 20%, because the transaction itself might cost around $20 dollars, and then the solver needs an incentive
to do the trade so maybe the actual slippage in price is 1% and it trades at 1.005 cost of DAI per USDC.

For a 1,000,000 USDC to DAI swap, this looks very different. Slippage might be around 0.005% where the solver gets $30, plus gas costs of
around $20 dollars, so setting the slippage to 0.5% or 1% to ensure that the swap is picked up is more than enough. The slippage tolerance
does not mean that's what the trade will definitely trade at. CoW Swap finds the best match and then executes at that price. Solvers are
competing at market prices for swaps all the time and they are incentivized to keep prices tight in order to get picked as executors.

Some tokens that are not "standard" ERC-20, such as Aave Interest Bearing Tokens (aTokens) are more gas consuming because the solvers
take into account the costs of wrapping and unwrapping the tokens. AaveSwapper supports aToken to aToken swaps though it is easier to
swap between underlyings.

Depending on the tokens and amounts, slippage will have to vary. A good heuristic is:

Trades of $1,000,000 worth of value or more, around 0.5-1% slippage.
Trades in the six figures, 1-2%.
Trades in the high five-figures, around 3%.
Trades below $15,000 worth of value, 5% slippage.
Trades in the low thousands and less are not really worth swapping because gas costs are a huge proportion of the swap.

The [CoW Swap UI](https://swap.cow.fi/#/1/swap/WETH) can be checked to get an estimate of slippage if executing at that time.

AaveSwapper uses Chainlink oracles for its slippage protection feature. Governance should enforce that all oracles set are
base-USD (ie: V3 oracles and not V2 oracles). AaveSwapper supports base-ETH swaps as well, but both bases have to be the same.
For example USDC/ETH to AAVE/ETH or USDC/USD to AAVE/USD. It does not support USDC/ETH to AAVE/USD swaps and this can lead to
bad trades because of price differences.

```
function limitSwap(
    address milkman,
    address priceChecker,
    address fromToken,
    address toToken,
    address recipient,
    uint256 amount,
    uint256 amountOut
  ) external onlyOwnerOrGuardian
```

Limit orders are used when wanting a specific price and not minding leaving an order open. When dealing with DAO swaps, knowing the price 5 days in advance is hard, and maybe relying on oracles is not what the DAO wants, especially dealing with low-liquidity tokens, or big orders that might move the market a lot but not the Oracle reference price.

The `amountOut` here is in the token that is to be RECEIVED. For example, let's say we want to swap 1 wETH for USDC, and the price is $2,000, and we want to get that or better, we would specify the swap in terms of the USDC to be received, in this case, 2,000 USDC. The `amountOut` is measured in the smallest atom of the currency. For tokens with 18 decimals, this would be quotedin wei. For 6 decimals, it would be in 0.000001 increments.

For example, if swapping 1 wETH for DAI, at a price of 2,000, then the `amountOut` needs to be `2000000000000000000000`. If swapping 1 wETH for USDC, the `amountOut` needs to be `2000000000` instead.

Swap fees/gas costs need to be taken into account, especially for smaller orders. For orders in the hundreds of thousands, or millions, this is just going to be a very tiny amount in percentage terms so it won't really matter much, but for a small order, it might. Take for example, the 1 wETH for USDC swap described above. If the limit order is at 2,000 and gas costs are $50, the trade will not settle until price trades at 2,050 because that needs to be taken from the value of the swap. Alternatively, the limit could be made 1,950 because the DAO wants the trade to settle once it hits 2,000 and not have to worry about it.

Limit orders are best suited for stable-to-stable swaps, especially bigger orders as the gas costs are going to be a tiny franction and swaps are likely to occurr rather easily.

```
 function twapSwap(
    address fromToken,
    address toToken,
    uint256 partSellAmount,
    uint256 minPartLimit,
    uint256 startTime,
    uint256 numParts,
    uint256 partDuration,
    uint256 span
  ) external onlyOwnerOrGuardian {
```

TWAP (or time-weighted average price) orders are used when wanting to average a certain price for a swap. For example, let's say the DAO wants to acquire TokenX but the DAO wants to do periodical purchases in order to get an average price and not worry about fluctuations. With TWAP orders, the DAO could for example purchase a certain amount of TokenX every Monday, every hour, or every first of the month.

`fromToken` is the token the user wants to sell, and `toToken` is the token that is to be acquired. `recipient` is the address that will receive the tokens, which is likely to be the Aave V3 Ethereum Collector.

For the TWAP specific orders, the parameters and their explanation are as follows:

`partSellAmount` is the amount of tokens of `fromToken` to be sold each time. For example, let's say the DAO wants to sell 100,000 units of DAI every week for one month, then `sellAmount` would be 25,000, as there will be 4 swaps total.

`minPartLimit` is the minimum amount the DAO is willing to accept per order. For example, following the above example, and with WETH trading at 2,000, which would yield 50 WETH (or 12.5 per each of the four orders), the minimum the DAO is willing to take is 12 (or 10, or anything).

`startTime` is when the orders can first take effect, in unix epoch seconds. For example, the DAO wants the orders to take place on Mondays, and the proposal is to be executed on a Sunday, one can specify the `startTime` as block.timestamp + 1 day to ensure it's on Monday.

`numParts` is the number of swaps to take place. In the example referenced above, this would be 4, to do a weekly swap for a month.

`partDuration` is how long to wait until the next order. Again, using the example above, this would be the uint256 representation of 1 week. If the DAO wanted daily buys, this would be 1 day in uint256.

`span` is to allow some extra customization on time of day, or days of the week the swaps will take place. Using the daily purchases example, the day has 86400 seconds, if the DAO only wanted to swap during the first half of the day, `span` would be set to 43200. The value 0 means the order can take place anytime during the interval (anytime during the day, week, month, etc).

```
function cancelSwap(
    address tradeMilkman,
    address fromToken,
    address toToken,
    uint256 amount,
    uint256 slippage
) external onlyOwnerOrGuardian
```

This methods cancels a pending trade. Trades should take just a couple of minutes to be picked up and traded, so if something's not right, the user
should assume something's off (bad slippage, market has moved too much), and should probably reach out via Telegram to the COW Swap team who will give extra insights.

Most likely, this function will be called when a swap is not getting executed because slippage might be too tight and there's no match for it.

```
function cancelLimitSwap(
    address tradeMilkman,
    address fromToken,
    address toToken,
    uint256 amount,
    uint256 amountOut
  ) external onlyOwnerOrGuardian
```

This methods cancels a pending limit trade. Trades should take just a couple of minutes to be picked up and traded, so if something's not right, the user
should think that something might be off.

For limit orders, keep in mind the price might be at the the limit price, but having to account for the cost of the swap might need the price to move a bit further. This should not matter for big swaps but it could be a thing in smaller swaps (especially around test swaps for validation).

```
function cancelTwapSwap(
    address fromToken,
    address toToken,
    uint256 partSellAmount,
    uint256 minPartLimit,
    uint256 startTime,
    uint256 numParts,
    uint256 partDuration,
    uint256 span
  ) external onlyOwnerOrGuardian
```

This method cancels a pending TWAP swap. Portions that have already happened will not be reimbursed, but any subsequent ones will be cancelled.

```

  function getExpectedOut(
    address priceChecker,
    uint256 amount,
    address fromToken,
    address toToken,
    address fromOracle,
    address toOracle
  ) public view returns (uint256)
```

Get the expected amount of tokens when doing a swap. Informational only.

`function rescueToken(address token) external onlyOwnerOrGuardian`
`function rescueToken(address token, uint256 amount) external onlyOwnerOrGuardian`

Functions for withdrawing tokens from `MainnetSwapSteward` to `Collector`. Overloaded function specifies amount. Regular function transfers balance of MainnetSwapSteward to Collector.

`function increaseTokenBudget(address token, uint256 budget) external`

Function for increasing the guardian's budget for a given token. Only callable by governance.

`function decreaseTokenBudget(address token, uint256 budget) external`

Function for decreasing the guardian's budget for a given token. Only callable by governance.

`function setSwappablePair(address fromToken, address toToken, bool allowed) external`

Function for setting a token pair combination to allowed/disallowed for swaps. Only callable by governance.

`function setTokenOracle(address token, address oracle) external`

Function for setting a token's oracle. Only callable by governance.

`function setPriceChecker(address newPriceChecker) external`

Function for setting the Price Checker smart contract to be used on regular swaps. Only callable by governance.

`function setLimitOrderPriceChecker(address newPriceChecker) external`

Function for setting the Price Checker smart contract to be used on limit order swaps. Only callable by governance.

`function setMilkman(address newMilkman) external`

Function for setting the Milkman (COW Swap) smart contract address. Only callable by governance.

`function setRelayer(address newRelayer) external`

Function for setting the Relayer (COW Swap) smart contract address. Only callable by governance.

`function setRelayer(address newRelayer, address[] calldata tokens) external`

Function for setting the Relayer (COW Swap) smart contract address. Allows passing an array of token addresses to set the allowance of the Relayer to zero for. Only callable by governance.

### Deployed Addresses

Please check out https://github.com/charlesndalton/milkman for updates on addresses.

Milkman: [`0x060373D064d0168931dE2AB8DDA7410923d06E88`](https://etherscan.io/address/0x060373D064d0168931dE2AB8DDA7410923d06E88)
Chainlink Price Checker: [`0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c`](https://etherscan.io/address/0xe80a1C615F75AFF7Ed8F08c9F21f9d00982D666c)
Limit Order Price Checker: [`0xcfb9Bc9d2FA5D3Dd831304A0AE53C76ed5c64802`](https://etherscan.io/address/0xcfb9Bc9d2FA5D3Dd831304A0AE53C76ed5c64802)
Mainnet: [`0x`]()

### Sample Swaps

#### Regular Swap

#### Limit Swaps

Sample ERC20 to ERC20 swap with 18 decimals: https://explorer.cow.fi/address/0x75a37623F8308eDaA2C21D8B51B91393A9E4033a
https://etherscan.io/tx/0x2186f0cabbbf1930b436783eca69328bfa5a7453c1c7d9a6ed9d7818b3ad9729

Sample ERC20 to ERC20 swap with 6 decimals:
https://explorer.cow.fi/address/0x141764c308997ec2a3AFE2cBAA1307610b126c01
https://etherscan.io/tx/0x135a6218866f050634bf52e699b93a9374c12cba19d2de104aa8296e86d0ce51

# Aave <> CoW Swap: SwapSteward

SwapSteward swaps Aave DAO treasury tokens through CoW Protocol, without Milkman. Every external address is a constructor argument, so the contract has no chain-specific code.

Every swap is a [Composable CoW](https://github.com/cowprotocol/composable-cow) conditional order. The steward moves the sell tokens from the Collector into a new `SwapEscrow`. The escrow is an EIP-1167 clone that owns the order and holds only that swap's tokens and relayer allowance. Only the steward can call `SwapEscrow.open` and `SwapEscrow.close`.

## How it works

- `swap(fromToken, toToken, amount, slippage)` is a market swap. Its minimum buy amount comes from the two token oracles at each poll.
- `twapSwap(fromToken, toToken, partSellAmount, minPartLimit, startTime, numParts, partDuration, span)` sells `partSellAmount * numParts` in equal parts on the TWAP handler. `minPartLimit` is the minimum buy amount per part.
- `cancelSwap(escrow)` calls `SwapEscrow.close`. It removes the order from ComposableCoW, sets the relayer allowance to 0 and sends the escrow's whole sell-token balance to the Collector.
- `getExpectedOut(amount, fromToken, toToken)` is a view. It returns the oracle expected out before slippage.

| Constant | Value |
| --- | --- |
| `MAX_SLIPPAGE` | `10_00`, 10% in basis points |
| `ORDER_LIFETIME` | `1 days` |
| `SEQUENCER_GRACE_PERIOD` | `1 hours` |

## Roles and limits

The owner is the DAO. The guardian acts without governance, within the limits the owner sets.

- **Owner only.** Only the owner can call `increaseTokenBudget`, `decreaseTokenBudget`, `setSwappablePair` and `setTokenOracle`. The guardian cannot approve a pair, set an oracle or raise a budget.
- **Owner or guardian.** The owner or the guardian can call `swap`, `twapSwap`, `cancelSwap`, both `rescueToken` overloads and `updateGuardian`.
- **Pairs.** `swap` and `twapSwap` revert with `UnrecognizedTokenSwap` unless the owner approved the ordered pair.
- **Budget.** A guardian swap reduces `tokenBudget[fromToken]` by its full sell amount and reverts with `InsufficientBudget` if the budget is lower. An owner swap does not use the budget. With `amount = type(uint256).max`, `swap` sells the Collector's balance of `fromToken` when the owner calls it and the remaining budget when the guardian calls it.
- **Slippage.** `swap` reverts with `InvalidSlippage` above `MAX_SLIPPAGE`.
- **Receiver.** `COLLECTOR` is immutable. It receives the bought tokens of every order and the tokens returned by every cancel and rescue.
- **Cancel.** `swaps` stores the sell token and the order hash of each open swap, not who opened it. Either role can cancel any open swap, including one the other role opened. A cancel does not restore budget. A guardian swap spends its amount from the budget whether it fills, expires or is cancelled.
- **Rescue.** `rescueToken` sends tokens the steward itself holds to the Collector. It never sends an escrow's tokens.
- **Guardian handover.** Budgets are per token, so a new guardian address has the same budget.

## Trust assumptions

The steward depends on the Collector, the token oracles and CoW Protocol.

- **Collector.** The steward must hold `FUNDS_ADMIN` on the Collector, because the Collector lets only that role call `transfer`. The steward takes tokens from the Collector only when it opens a swap.
- **Oracle prices.** Prices come from `latestAnswer` only. `setTokenOracle` requires 8 decimals and a positive answer. No contract checks the price oracles for staleness. The steward does not check what an oracle quotes, so the owner must set both oracles of a pair in the same currency.
- **SVR feeds.** A Chainlink SVR feed uses a DualAggregator. If a token oracle is the secondary proxy of an SVR feed, a round reported on the primary route becomes visible only after the aggregator's cutoff time. The price an order uses can lag the newest round.
- **Slippage cap.** The minimum buy amount is the oracle expected out times `(10_000 - slippage) / 10_000`. With `MAX_SLIPPAGE` at `10_00` the lowest minimum buy amount is 90% of the oracle expected out, rounded down. The cap is relative to the oracle price, not to a market price.
- **Token decimals.** `OracleMath.getExpectedOut` calls `decimals()` on both tokens. `swap` does not call `decimals()` when it creates the order, so a token without `decimals()` still moves into the escrow. The handler then reverts on every poll and `getExpectedOut` reverts. The owner approves every pair and is trusted to approve only tokens that implement `decimals()`. `twapSwap` reads no oracle and no `decimals()`.
- **Settlement and solvers.** Only a solver on the allow-list of the `GPv2Settlement` authenticator can settle. The authenticator, `GPv2AllowListAuthentication`, runs behind an EIP-1967 proxy. Its manager adds and removes solvers. The proxy admin can replace the manager with `setManager` and can upgrade the implementation. The steward controls none of this. A solver decides when and how to fill. The settlement rejects an order past its `validTo` or below its minimum buy amount.
- **Vault relayer.** `SwapEscrow.open` approves the relayer for the exact amount sent to the escrow. That amount is the sell amount for `swap` and `partSellAmount * numParts` for `twapSwap`. CoW's `GPv2VaultRelayer` pulls only when the settlement contract calls it. The steward checks only that the relayer address is not zero.
- **Watch-tower.** CoW's watch-tower polls ComposableCoW for the order and posts it to the CoW API. `open` calls `create` with `dispatch = true`, which emits the `ConditionalOrderCreated` event the watch-tower indexes. A watch-tower outage stops only the automatic polling and posting. An order already posted can still settle until its `validTo`, as long as `verify` passes. `getTradeableOrderWithSignature` on ComposableCoW is public, so anyone can post the order. `GPv2Settlement` checks the solver and the signature, not who posted the order. `cancelSwap` is the way to stop an order and return the tokens.
- **Order creation is not validated.** `ComposableCoW.create` only checks that the handler is not the zero address. It does not validate TWAP data, and invalid TWAP data makes the handler revert on every poll. So `twapSwap` calls `TWAPOrder.validate` before it moves any funds. `TWAPOrder.validate` comes from composable-cow pinned at commit `c0435953` (tag `ack3-rev2.0`) in `lib/composable-cow`. The steward does not check that `TWAP_HANDLER` applies the same rules.
- **L2 sequencer.** When `SEQUENCER_UPTIME_FEED` is set, `OracleMarketOrder` reverts with `PollTryNextBlock` while the feed reports the sequencer as down or reports an invalid start time. It reverts with `PollTryAtEpoch` until `SEQUENCER_GRACE_PERIOD` has passed since the sequencer came back up. A zero feed address disables the check, for chains without a sequencer such as Mainnet. The TWAP path has no sequencer check. `TWAP_HANDLER` takes no feed and `twapSwap` passes none.
- **Escrow after a fill.** Before `validUntil`, the market handler's `getTradeableOrder` reverts with `OrderNotValid("insufficient balance")` when the escrow holds less than `sellAmount`, as it does after a fill. After `validUntil` it reverts with `OrderNotValid("order expired")` instead, because the expiry check runs first. The watch-tower drops the order on `OrderNotValid`. The TWAP handler does not read the escrow balance. The swap stays in `swaps` and the order stays registered until `cancelSwap` calls `close`.
- **Price manipulation.** A market order reads no on-chain spot pool, so moving a pool does not move its minimum buy amount. The generated order and its hash change exactly when the computed buy amount changes. The buy amount comes from both oracle answers and both tokens' `decimals()`, and is rounded down. An answer change that leaves the rounded buy amount the same keeps the same order. A changed buy amount makes the old order revert with `OrderNotValid("invalid hash")`. `swap` sets `validUntil` to `block.timestamp + ORDER_LIFETIME` at creation, which bounds how long the order is valid. A TWAP's `minPartLimit` does not change after creation and must be above 0. Nothing checks it against an oracle. For a guardian TWAP, the budget is the only bound on the amount sold at that price floor.
- **External control.** The steward and its escrows hold ComposableCoW, both handlers and the relayer as immutables and cannot change them after construction. ComposableCoW decides whether to authorise an escrow's order and calls the handler's `verify`. Its source has no owner, admin or upgrade function. The TWAP handler's source has no such function either. The handler sets each part's time window. The steward does not check the code at `MARKET_ORDER_HANDLER` or `TWAP_HANDLER`.
