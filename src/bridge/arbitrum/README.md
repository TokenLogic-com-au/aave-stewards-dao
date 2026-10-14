# Aave Arbitrum -> Mainnet ERC20 Bridge Steward

Bridging funds from the Arbitrum Collector to Ethereum mainnet currently requires a governance proposal. This Steward delegates that responsibility to a Guardian, consistent with the approach taken on Polygon and Optimism.

Adapted from the existing [AaveArbEthERC20Bridge](https://arbiscan.io/address/0x0335ffa9af5ce05590d6c9a75b645470e07744a9) (`0x0335ffa9af5ce05590d6c9a75b645470e07744a9`) to include a Steward Role so the AFC (guardian) can bridge funds without requiring an AIP submission each time.

The official Arbitrum documentation can be found [here](https://docs.arbitrum.io/build-decentralized-apps/token-bridging/token-bridge-erc20).

## Security Considerations

Not all ERC20 tokens on Arbitrum are compatible with the standard gateway. Each token uses a specific L2 gateway for bridging. Governance must only allowlist tokens that can be bridged via their respective gateways. Tokens that rely on custom bridges or external protocols must **NOT** be added to the token mapping:

- **Native USDC**: Bridged via Circle's CCTP, not through the standard gateway.
- **wstETH**: Uses a custom bridge maintained by Lido.

## Setup

The steward pulls funds from the Arbitrum Collector via `Collector.transfer`, so governance must grant it the `FUNDS_ADMIN_ROLE` on the Arbitrum Collector. No token approvals are required. Governance must also allowlist each bridgeable token via `setTokenMapping`.

## Functions

`function bridge(address token, uint256 amount) external`

Callable on Arbitrum by owner or guardian. Pulls `amount` of `token` from the Arbitrum Collector, then bridges it to the Mainnet Collector via the L2 Gateway Router, which resolves the correct gateway for the token. The token must have an L1 mapping set via `setTokenMapping`.

`function bridgeEth(uint256 amount) external`

Callable on Arbitrum by owner or guardian. Bridges `amount` of native ETH already held by the contract to the Mainnet Collector via the `ArbSys` precompile (`withdrawEth`). Reverts if the contract balance is lower than `amount`.

`function setTokenMapping(address l2Token, address l1Token) external`

Callable on Arbitrum by owner only (governance). Sets the L1 token address corresponding to an L2 token. The pair is validated against the L2 Gateway Router's `calculateL2TokenAddress(l1Token)`. Reverts if a mapping already exists; remove it first via `removeTokenMapping`.

**Only tokens that have been mapped can be bridged.** The mapping starts empty; governance must explicitly allow each token.

`function removeTokenMapping(address l2Token) external`

Callable on Arbitrum by owner only (governance). Removes the L1 token mapping for a given L2 token, disabling bridging for that token.

`function executeOutbox(bytes32[] proof, uint256 index, address l2Sender, address to, uint256 l2Block, uint256 l1Block, uint256 l2Timestamp, uint256 value, bytes data) external`

Callable on Mainnet by anyone. Finalizes an L2-to-L1 message by forwarding it to the Arbitrum Outbox. See [Finalizing the Bridge](#finalizing-the-bridge).

`function rescueToken(address token) external`

Callable on Arbitrum by owner or guardian. Rescues ERC20 tokens stuck in the contract back to the Arbitrum Collector.

`function rescueEth() external`

Callable on Arbitrum by owner or guardian. Rescues ETH stuck in the contract back to the Arbitrum Collector.

`function config(address l2Token) external view returns (address l1Token)`

Returns the L1 token mapped to `l2Token`, or the zero address if the token is not allowlisted.

## Finalizing the Bridge

After calling `bridge()` on Arbitrum, it takes ~7 days for the withdrawal to be available (optimistic rollup). Once available, the withdrawal can be finalized on Mainnet.

A burn proof is generated via the `aave-cli` tool, which can be found [here](https://github.com/TokenLogic-com-au/aave-cli-tools).

The command to generate the proof is:

`yarn start arbitrum-bridge-exit <TX_HASH> <INDEX> <ARBITRUM_BLOCK_OF_TX>`

Where `TX_HASH` is the hash of the bridge transaction on Arbitrum, `INDEX` is the withdrawal index (if there are 3 tokens bridged in the same transaction, the indexes will be 0, 1 and 2), and `ARBITRUM_BLOCK_OF_TX` is the block the bridge transaction happened at.

The generated proof and message parameters are then passed to `executeOutbox` on Mainnet.

## Known Gateway Addresses (L2)

For reference only. The gateway is resolved by the L2 Gateway Router at bridge time and is not configured on the steward.

| Token  | Gateway                                      |
| ------ | -------------------------------------------- |
| USDC.e | `0x096760F208390250649E3e8763348E783AEF5562` |
| WETH   | `0x6c411aD3E74De3E7Bd422b94A27770f5B86C623B` |
| WBTC   | `0x09e9222E96E7B4AE2a407B98d48e330053351EEe` |
| DAI    | `0x09e9222E96E7B4AE2a407B98d48e330053351EEe` |
| LINK   | `0x09e9222E96E7B4AE2a407B98d48e330053351EEe` |
| ARB    | `0x09e9222E96E7B4AE2a407B98d48e330053351EEe` |

## Transactions

| Token | Bridge | Exit |
| ----- | ------ | ---- |
| TBD   |        |      |

## Deployed Address

Arbitrum: [TBD](https://arbiscan.io/address/TBD)
