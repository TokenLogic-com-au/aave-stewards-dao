// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IArbEthERC20BridgeSteward
/// @author efecarranza.eth (TokenLogic)
/// @notice Defines the behaviour of the ArbEthERC20BridgeSteward.
interface IArbEthERC20BridgeSteward {
    /// @dev Contract balance is lower than the requested bridge amount
    error InsufficientBalance();

    /// @dev Function called on the wrong chain
    error InvalidChain();

    /// @dev `l2Token` does not match the canonical mapping for `l1Token`
    error InvalidL2Token();

    /// @dev Provided address cannot be the zero-address
    error InvalidZeroAddress();

    /// @dev Amount must be greater than zero
    error InvalidZeroAmount();

    /// @dev Token mapping already exists; remove it before setting a new one
    error TokenAlreadySet();

    /// @dev Token has no L1 mapping set — call `setTokenMapping` first
    error TokenNotSet();

    /// @notice Emitted when bridging an ERC20 token from Arbitrum to Mainnet
    /// @param token Address of the Arbitrum token
    /// @param l1Token Address of the equivalent Mainnet token
    /// @param amount Amount of tokens bridged
    /// @param to Address receiving the token on Mainnet
    event Bridge(
        address indexed token,
        address indexed l1Token,
        uint256 amount,
        address indexed to
    );

    /// @notice Emitted when bridging native ETH from Arbitrum to Mainnet
    /// @param amount Amount of ETH bridged
    /// @param to Address receiving the ETH on Mainnet
    event BridgeEth(uint256 amount, address indexed to);

    /// @notice Emitted when an L2-to-L1 message is finalized through the Arbitrum Outbox
    /// @param l2Sender L2 address that initiated the original message
    /// @param to L1 target address that received the message
    event OutboxExecuted(address indexed l2Sender, address indexed to);

    /// @notice Emitted when a token mapping is updated
    /// @param l2Token Address of the token on Arbitrum
    /// @param l1Token Address of the corresponding token on Mainnet
    event TokenMappingUpdated(address indexed l2Token, address l1Token);

    /// @notice Emitted when a token mapping is removed
    /// @param l2Token Address of the token on Arbitrum that was removed
    event RemovedTokenMapping(address indexed l2Token);

    /// @notice Bridges an ERC20 from the Arbitrum Collector to the Mainnet Collector
    /// @param token L2 token address (must have an L1 mapping configured)
    /// @param amount Amount to bridge
    function bridge(address token, uint256 amount) external;

    /// @notice Bridges native ETH already sitting in the contract to the Mainnet Collector
    /// @param amount Amount of ETH to bridge
    function bridgeEth(uint256 amount) external;

    /// @notice Sets a token mapping for bridging
    /// @param l2Token Address of the token on Arbitrum
    /// @param l1Token Address of the corresponding token on Mainnet
    function setTokenMapping(address l2Token, address l1Token) external;

    /// @notice Removes an existing token mapping
    /// @param l2Token Address of the token on Arbitrum
    function removeTokenMapping(address l2Token) external;

    /// @notice Finalizes an L2-to-L1 message on Mainnet by forwarding it to the Outbox
    /// @param proof Merkle proof of the message inclusion in the L2 outbox
    /// @param index Index of the message in the outbox
    /// @param l2Sender L2 address that initiated the message
    /// @param to L1 target address of the message
    /// @param l2Block L2 block at which the message was emitted
    /// @param l1Block L1 block at which the message was emitted
    /// @param l2Timestamp L2 timestamp at which the message was emitted
    /// @param value ETH value forwarded with the message
    /// @param data Calldata to forward to `to`
    function executeOutbox(
        bytes32[] calldata proof,
        uint256 index,
        address l2Sender,
        address to,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        uint256 value,
        bytes calldata data
    ) external;

    /// @notice Rescues stuck ERC20 tokens back to the Arbitrum Collector
    /// @param token Address of the ERC20 token to rescue
    function rescueToken(address token) external;

    /// @notice Rescues stuck ETH back to the Arbitrum Collector
    function rescueEth() external;

    /// @notice Returns the Arbitrum L2 Gateway Router used to initiate withdrawals
    function L2_GATEWAY_ROUTER() external view returns (address);

    /// @notice Returns the L1 Outbox used to finalize L2-to-L1 messages on Mainnet
    function MAINNET_OUTBOX() external view returns (address);

    /// @notice Returns the L1 token configured for `l2Token`
    /// @param l2Token Address of the token on Arbitrum
    /// @return l1Token Address of the corresponding token on Mainnet
    function config(address l2Token) external view returns (address l1Token);
}
