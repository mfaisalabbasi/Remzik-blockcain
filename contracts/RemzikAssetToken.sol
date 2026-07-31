// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface IIdentityRegistry {
    function isClearToTrade(address _user) external view returns (bool);
}

contract RemzikAssetToken is ERC20, ERC20Permit, ERC20Votes, AccessControl, Pausable {
    bytes32 public constant COMPLIANCE_BYPASS_ROLE = keccak256("COMPLIANCE_BYPASS_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant RECOVERY_ROLE = keccak256("RECOVERY_ROLE"); // Phase 10: Role for RecoveryManager
    
    IIdentityRegistry public immutable registry;
    string public metadataHash;

    event MetadataUpdated(string newHash);
    event LiquidationActivated();

    error TokenPaused();
    error ComplianceFailed(address account);

    constructor(
        string memory name,
        string memory symbol,
        uint256 supply,
        string memory _metadataHash,
        address _registry,
        address _treasury,
        address _admin
    ) ERC20(name, symbol) ERC20Permit(name) {
        registry = IIdentityRegistry(_registry);
        metadataHash = _metadataHash;
        
        // Grant admin rights to AssetFactory so it can assign GOVERNANCE_ROLE & RECOVERY_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(COMPLIANCE_BYPASS_ROLE, _treasury);
        
        _mint(_treasury, supply);
    }

    // Phase 9: Kill-Switch triggered by PropertyGovernance
    function activateLiquidation() external onlyRole(GOVERNANCE_ROLE) {
        _pause();
        emit LiquidationActivated();
    }

    // Ability to resume trading after liquidation/maintenance
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function setMetadataHash(string memory newHash) external onlyRole(DEFAULT_ADMIN_ROLE) {
        metadataHash = newHash;
        emit MetadataUpdated(newHash);
    }

    // --- Phase 10: Authorized Wallet Recovery Execution ---
    
    /**
     * @notice Allows the designated RecoveryManager (holding RECOVERY_ROLE) to execute a forced transfer 
     *         from a lost/compromised wallet to a newly verified recovery wallet address.
     */
    function forcedTransfer(address from, address to, uint256 amount) external onlyRole(RECOVERY_ROLE) returns (bool) {
        // We use internal _update directly to execute the balance shift safely under institutional override
        _update(from, to, amount);
        return true;
    }

    // --- Override Logic for ERC20Votes and Compliance ---
    
    function _update(address from, address to, uint256 value) 
        internal 
        override(ERC20, ERC20Votes) 
    {
        if (paused()) revert TokenPaused();

        // 🛡️ Phase 10 Safe Bypass: If the transaction is driven by an authorized recovery entity 
        // or compliance bypass role, we bypass standard trading registry checks for old/compromised wallets.
        bool isBypassed = hasRole(COMPLIANCE_BYPASS_ROLE, msg.sender) || hasRole(RECOVERY_ROLE, msg.sender);

        if (!isBypassed) {
            if (from != address(0) && !hasRole(COMPLIANCE_BYPASS_ROLE, from)) {
                if (!registry.isClearToTrade(from)) revert ComplianceFailed(from);
            }
            
            if (to != address(0) && !hasRole(COMPLIANCE_BYPASS_ROLE, to)) {
                if (!registry.isClearToTrade(to)) revert ComplianceFailed(to);
            }
        }
        
        super._update(from, to, value);
    }

    function nonces(address owner) 
        public 
        view 
        override(ERC20Permit, Nonces) 
        returns (uint256) 
    {
        return super.nonces(owner);
    }

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }
}