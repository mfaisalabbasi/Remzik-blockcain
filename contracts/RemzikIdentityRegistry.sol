// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title RemzikIdentityRegistry
 * @notice Production compliance ledger for the Remzik RWA ecosystem.
 * @dev Tracks both KYC approval and security freeze states natively on-chain.
 */
contract RemzikIdentityRegistry {
    address public owner;

    // Dual-flag tracking structure to mirror Web2 user states perfectly
    struct IdentityState {
        bool isVerified; // Handled via handleKycAction / approveKyc / rejectKyc
        bool isFrozen;   // Handled via toggleAccountFreeze (Emergency switch)
    }

    mapping(address => IdentityState) private _registry;

    // --- Custom Errors for Gas Optimization ---
    error UnauthorizedCaller(address caller);
    error InvalidAddress();

    // --- Web3 Events for Subgraph / Backend Listening Sync ---
    event IdentityUpdated(address indexed investor, bool isVerified, address indexed authorizedBy);
    event IdentityFreezeToggled(address indexed investor, bool isFrozen, address indexed authorizedBy);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        if (msg.sender != owner) revert UnauthorizedCaller(msg.sender);
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /**
     * @notice Updates the verification/KYC status of an investor.
     * @dev Shakes hands with `handleKycAction`, `approveKyc`, and `rejectKyc` in NestJS.
     * @param investor The wallet address of the user.
     * @param status True to verify, false to revoke.
     */
    function registerIdentity(address investor, bool status) external onlyOwner {
        if (investor == address(0)) revert InvalidAddress();
        _registry[investor].isVerified = status;
        emit IdentityUpdated(investor, status, msg.sender);
    }

    /**
     * @notice Emergency freeze/unfreeze safety switch for compliance administration.
     * @dev Shakes hands with `toggleAccountFreeze` in NestJS.
     * @param investor The wallet address of the user.
     * @param freezeStatus True to lock completely, false to restore.
     */
    function toggleFreeze(address investor, bool freezeStatus) external onlyOwner {
        if (investor == address(0)) revert InvalidAddress();
        _registry[investor].isFrozen = freezeStatus;
        emit IdentityFreezeToggled(investor, freezeStatus, msg.sender);
    }

    /**
     * @notice Gateway validation check used by Remzik RWA Security Tokens before transfers.
     * @dev User MUST be verified AND NOT frozen to trade assets.
     * @param investor The wallet address checking clearing.
     * @return true only if the investor is verified AND active (not frozen).
     */
    function isClearToTrade(address investor) external view returns (bool) {
        IdentityState memory state = _registry[investor];
        if (state.isFrozen) return false;
        return state.isVerified;
    }

    /**
     * @notice Independent read view for your backend dashboard/state audits.
     * @param investor The wallet address to inspect.
     * @return verified The current KYC verification status.
     * @return frozen The current security freeze status.
     */
    function getIdentityState(address investor) external view returns (bool verified, bool frozen) {
        IdentityState memory state = _registry[investor];
        return (state.isVerified, state.isFrozen);
    }

    /**
     * @notice Safe ownership transfer process for system contracts.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
