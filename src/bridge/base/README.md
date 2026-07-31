# Aave Base -> Mainnet ERC20 Bridge Steward

Bridging funds from the Base Collector to Ethereum mainnet currently requires a governance proposal. This Steward delegates that responsibility to a Guardian, consistent with the approach taken on Polygon, Arbitrum, and Optimism.

The official Base bridge documentation can be found [here](https://docs.base.org/chain/bridges).

## Security Considerations

Not all ERC20 tokens on Base are compatible with the Standard Bridge. Governance must only allowlist tokens whose L2 representation uses the standard `OptimismMintableERC20` pattern (e.g. USDbC). The L2 -> L1 mapping is set explicitly by the owner and validated against the token's on-chain `remoteToken()` / `l1Token()` at configuration time.

Tokens that rely on custom bridges or external protocols must NOT be added to the token mapping:

- **DAI / USDS**: Use MakerDAO/Sky's custom SkyLink (OP Token) bridge, not the Standard Bridge.
- **Native USDC** (`0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`): Bridged via Circle's CCTP, not through the Standard Bridge.

Incompatible tokens are also rejected on-chain: `setTokenMapping` validates the pair against the token's `remoteToken()` / `l1Token()`, so a non-standard token cannot be mapped.

For the full list of token bridges, see the [official Base bridge documentation](https://docs.base.org/chain/bridges).

## Functions

`function bridge(address token, uint256 amount) external`

Callable on Base by owner or guardian. Pulls `amount` of `token` from the Base Collector, then bridges to the Mainnet Collector via the Standard Bridge. The token must have a mapping previously set by governance.

`function setTokenMapping(address l2Token, address l1Token) external`

Callable on Base by owner only (governance). Adds an L2 -> L1 token mapping. The pair is validated against the L2 token's `remoteToken()` / `l1Token()`; an existing mapping must be removed before it can be changed.

`function removeTokenMapping(address l2Token) external`

Callable on Base by owner only (governance). Removes an existing L2 -> L1 token mapping.

`function rescueToken(address token) external`

Callable on Base by owner or guardian. Rescues ERC20 tokens stuck in the contract back to the Base Collector.

`function rescueEth() external`

Callable on Base by owner or guardian. Rescues ETH stuck in the contract back to the Base Collector.

## Proving The Message

In order to finalize the bridge from Base to Mainnet, there are two steps required. Firstly, one must prove the message. There is no way to do this on-chain with Foundry so we rely on the OP Stack SDK via TokenLogic's CLI tool.

[The CLI tool can be found here](https://github.com/TokenLogic-com-au/aave-cli-tools).

The first command can be run a few minutes to an hour after the bridge transaction takes place.

Once the message is proven, around 7 days later from the transaction, it will be available to be finalized as Base is an optimistic rollup.

## Finalizing

After the challenge period, run the finalize command from the CLI to complete the withdrawal on Mainnet.

## Transactions

| Token | Bridge | Prove | Finalize |
| ----- | ------ | ----- | -------- |
| TBD   |        |       |          |

## Deployed Address

Base: [TBD](https://basescan.org/address/TBD)
