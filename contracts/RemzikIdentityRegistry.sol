// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract RemzikIdentityRegistry is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    bytes32 public constant KYC_MANAGER_ROLE = keccak256("KYC_MANAGER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    address public recoveryManager; // Phase 10: Authorized RecoveryManager contract address

    struct IdentityState {
        bool isVerified;
        bool isFrozen;
    }

    mapping(address => IdentityState) private _registry;
    
    // SYSTEM WALLETS: Automatically bypass standard KYC/verification checks
    mapping(address => bool) public isSystemWallet;

    error UnauthorizedCaller(address caller);
    error InvalidAddress();

    event IdentityUpdated(address indexed investor, bool isVerified, address indexed authorizedBy);
    event IdentityFreezeToggled(address indexed investor, bool isFrozen, address indexed authorizedBy);
    event SystemWalletUpdated(address indexed wallet, bool status, address indexed authorizedBy);
    event RecoveryManagerUpdated(address indexed newRecoveryManager, address indexed authorizedBy);

    // Phase 10: Modifier allowing either the DEFAULT_ADMIN_ROLE or the authorized RecoveryManager contract
    modifier onlyAuthorizedRecovery() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender) && msg.sender != recoveryManager) revert UnauthorizedCaller(msg.sender);
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __AccessControl_init();

        // Automatically grant all administrative and operational roles to the contract deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(KYC_MANAGER_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        
        // Automatically whitelist the contract deployer as a system wallet
        isSystemWallet[msg.sender] = true;
    }

    function registerIdentity(address investor, bool status) external onlyRole(KYC_MANAGER_ROLE) {
        if (investor == address(0)) revert InvalidAddress();
        _registry[investor].isVerified = status;
        emit IdentityUpdated(investor, status, msg.sender);
    }

    function batchRegisterIdentity(address[] calldata investors, bool status) external onlyRole(KYC_MANAGER_ROLE) {
        for (uint256 i = 0; i < investors.length; i++) {
            if (investors[i] == address(0)) revert InvalidAddress();
            _registry[investors[i]].isVerified = status;
            emit IdentityUpdated(investors[i], status, msg.sender);
        }
    }

    // Phase 10: Enables RecoveryManager to update verification status atomically during asset recovery
    function setVerificationStatus(address investor, bool status) external onlyAuthorizedRecovery {
        if (investor == address(0)) revert InvalidAddress();
        _registry[investor].isVerified = status;
        emit IdentityUpdated(investor, status, msg.sender);
    }

    // Phase 10: Set the authorized RecoveryManager contract address
    function setRecoveryManager(address _recoveryManager) external onlyRole(OPERATOR_ROLE) {
        if (_recoveryManager == address(0)) revert InvalidAddress();
        recoveryManager = _recoveryManager;
        emit RecoveryManagerUpdated(_recoveryManager, msg.sender);
    }

    function toggleFreeze(address investor, bool freezeStatus) external onlyRole(KYC_MANAGER_ROLE) {
        if (investor == address(0)) revert InvalidAddress();
        _registry[investor].isFrozen = freezeStatus;
        emit IdentityFreezeToggled(investor, freezeStatus, msg.sender);
    }

    /// @notice Allows designated OPERATOR_ROLE to configure infrastructure wallets (like Treasuries or Factories)
    function setSystemWallet(address wallet, bool status) external onlyRole(OPERATOR_ROLE) {
        if (wallet == address(0)) revert InvalidAddress();
        isSystemWallet[wallet] = status;
        emit SystemWalletUpdated(wallet, status, msg.sender);
    }

    function isClearToTrade(address investor) external view returns (bool) {
        // System wallets automatically bypass standard compliance rules
        if (isSystemWallet[investor]) return true;

        IdentityState memory state = _registry[investor];
        if (state.isFrozen) return false;
        return state.isVerified;
    }

    function getIdentityState(address investor) external view returns (bool verified, bool frozen) {
        if (isSystemWallet[investor]) {
            return (true, false);
        }
        IdentityState memory state = _registry[investor];
        return (state.isVerified, state.isFrozen);
    }

    // Required by UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // Storage gap for future upgrades safety
    uint256[48] private __gap;
}