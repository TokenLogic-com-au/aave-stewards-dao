# Aave Optimism -> Mainnet ERC20 Bridge Steward

Bridging funds from the Optimism Collector to Ethereum mainnet currently requires a governance proposal. This Steward delegates that responsibility to a Guardian, consistent with the approach taken on Polygon and Arbitrum.

Adapted from the existing [AaveOpEthERC20Bridge](https://optimistic.etherscan.io/address/0xc3250a20f8a7bbdd23ade87737ee46a45fe5543e) (`0xc3250A20F8a7BbDd23adE87737EE46A45Fe5543E`) to include a Steward Role so the AFC (guardian) can bridge funds without requiring an AIP submission each time.

The official Optimism documentation can be found [here](https://docs.optimism.io/builders/app-developers/bridging/standard-bridge).

## Security Considerations

Not all ERC20 tokens on Optimism are compatible with the Standard Bridge. Only tokens whose L2 representation uses the standard `OptimismMintableERC20` pattern should be allowlisted (e.g. USDC.e, WETH, LINK). Tokens that rely on custom bridges or external protocols must **NOT** be added to the token mapping:

- **DAI**: Uses a dedicated DAI bridge and cannot be withdrawn via the Standard Bridge.
- **USDT**: Uses a custom bridging mechanism; the Standard Bridge will reject it.
- **Native USDC**: Bridged via Circle's CCTP, not through the Standard Bridge.

## Functions

`function bridge(address token, uint256 amount) external`

Callable on Optimism by owner or guardian. Pulls `amount` of `token` from the Optimism Collector, then bridges to the Mainnet Collector via the Standard Bridge. The ERC20 token must be an OptimismBurnableERC20 in order to be bridged. The token must have an L1 mapping set via `setTokenMapping`.


`function setTokenMapping(address l2Token, address l1Token) external`

Callable on Optimism by owner only (governance). Sets or removes the L1 token address corresponding to an L2 token. Setting `l1Token` to `address(0)` disables bridging for that token.

**Only tokens that have been mapped can be bridged.** The mapping starts empty; governance must explicitly allow each token.

`function removeTokenMapping(address l2Token) external`

Callable on Optimism by owner only (governance). Removes the L1 token mapping for a given L2 token, disabling bridging for that token.

`function rescueToken(address token) external`

Callable on Optimism by owner or guardian. Rescues ERC20 tokens stuck in the contract back to the Optimism Collector.

`function rescueEth() external`

Callable on Optimism by owner or guardian. Rescues ETH stuck in the contract back to the Optimism Collector.

## Proving The Message

In order to finalize the bridge from Optimism to Mainnet, there are two steps required. Firstly, one must prove the message. Unfortunately, there's no way to do this on-chain with Foundry so we have to rely on the Optimism SDK by utilizing TokenLogic's CLI tool (forked off of BGD's aave-cli).

[The CLI tool can be found here](https://github.com/TokenLogic-com-au/aave-cli-tools).

The first command can be run a few minutes to an hour after the bridge transaction takes place.

The script can be run with the following command:

`yarn start optimism-prove-message <TX_HASH> <INDEX>` where TX_HASH is the transaction hash where the bridge took place and INDEX is the index of the ERC20 token in terms of how many tokens were bridged in the same transaction. For just one token, INDEX will be 0. For multiple, start from 0 and go up by one.

Once the message is proven, around 7 days later from the transaction, it will be available to be finalized as Optimism is an optimistic rollup.

## Finalizing

[The CLI can be found here](https://github.com/TokenLogic-com-au/aave-cli-tools).

Just like when proving the message, there's a command in order to finalize the bridge.

`yarn start optimism-finalize-bridge <TX_HASH> <INDEX>` where TX_HASH is the transaction hash where the bridge took place and INDEX is the index of the ERC20 token in terms of how many tokens were bridged in the same transaction. For just one token, INDEX will be 0. For multiple, start from 0 and go up by one.

## Transactions

| Token | Bridge | Prove | Finalize |
| ----- | ------ | ----- | -------- |
| TBD   |        |       |          |

## Deployed Address

Optimism: [TBD](https://optimistic.etherscan.io/address/TBD)
