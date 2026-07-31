// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

interface IERC3643AssetToken {
    function forcedTransfer(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IIdentityRegistry {
    function setVerificationStatus(address userAddress, bool status) external;
}

contract RecoveryManager is AccessControl {
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    address public identityRegistry;

    event WalletRecovered(
        address indexed oldWallet,
        address indexed newWallet,
        address indexed tokenAddress,
        uint256 amount,
        uint256 timestamp
    );

    constructor(address _identityRegistry, address admin) {
        require(_identityRegistry != address(0), "Invalid registry address");
        identityRegistry = _identityRegistry;
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(AGENT_ROLE, admin);
    }

    /**
     * @notice Atomically executes wallet recovery: transfers tokens first, 
     *         then updates registry compliance status only on total success.
     */
    function recoverWallet(
        address tokenAddress,
        address oldWallet,
        address newWallet,
        uint256 amount
    ) external onlyRole(AGENT_ROLE) {
        require(tokenAddress != address(0), "Invalid token address");
        require(oldWallet != address(0), "Invalid old wallet");
        require(newWallet != address(0), "Invalid new wallet");
        require(oldWallet != newWallet, "Same wallet address");

        // 1. Execute the token transfer via ERC-3643 forced transfer mechanism.
        // If this fails or reverts, the entire transaction rolls back automatically,
        // ensuring the old wallet remains active and untouched.
        bool success = IERC3643AssetToken(tokenAddress).forcedTransfer(oldWallet, newWallet, amount);
        require(success, "Forced token transfer failed");

        // 2. Atomically update the Identity Registry compliance statuses
        IIdentityRegistry(identityRegistry).setVerificationStatus(oldWallet, false);
        IIdentityRegistry(identityRegistry).setVerificationStatus(newWallet, true);

        // 3. Emit immutable audit event for the backend indexer
        emit WalletRecovered(oldWallet, newWallet, tokenAddress, amount, block.timestamp);
    }

    function updateIdentityRegistry(address newRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRegistry != address(0), "Invalid registry address");
        identityRegistry = newRegistry;
    }
}