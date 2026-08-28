// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IRemzikIdentityRegistry {
    function isClearToTrade(address investor) external view returns (bool);
}

// Interface to interact with the property token for transfers
interface IRemzikAssetToken {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract TreasuryVault is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    IRemzikIdentityRegistry public identityRegistry;
    
    // The specific property ID this vault belongs to
    bytes32 public propertyId;

    // Address of the fractional property token (`RemzikAssetToken`)
    address public assetToken;

    mapping(address => bool) public acceptedStablecoins;
    uint256 public totalVaultDeposits;

    event StablecoinDeposited(
        address indexed investor,
        bytes32 indexed propertyId,
        address indexed stablecoin,
        uint256 amount,
        uint256 timestamp
    );
    event StablecoinUpdated(address indexed stablecoin, bool status);
    event FundsWithdrawn(address indexed token, address indexed recipient, uint256 amount);
    event AssetTokenUpdated(address indexed newToken);
    event TokensReleased(address indexed token, address indexed to, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _registry,
        address _admin,
        bytes32 _propertyId,
        address _assetToken,
        address _defaultStablecoin // 👈 Added: Atomic auto-whitelisting parameter
    ) public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(UPGRADER_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);

        require(_registry != address(0), "Invalid registry");
        require(_assetToken != address(0), "Invalid asset token address");

        identityRegistry = IRemzikIdentityRegistry(_registry);
        propertyId = _propertyId;
        assetToken = _assetToken;

        // 🛡️ Atomic Stablecoin Whitelisting during initialization
        if (_defaultStablecoin != address(0)) {
            acceptedStablecoins[_defaultStablecoin] = true;
            emit StablecoinUpdated(_defaultStablecoin, true);
        }
        
        emit AssetTokenUpdated(_assetToken);
    }

    // Admin function to update the property's ERC-20 token contract if needed later
    function setAssetToken(address _assetToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_assetToken != address(0), "Invalid token address");
        assetToken = _assetToken;
        emit AssetTokenUpdated(_assetToken);
    }

    /**
     * @notice Deposit stablecoins directly into this property's dedicated vault and receive fractional tokens.
     */
    function deposit(address stablecoin, uint256 amount) external {
        require(acceptedStablecoins[stablecoin], "Stablecoin not accepted");
        require(amount > 0, "Amount must be zero");
        require(assetToken != address(0), "Asset token not configured");

        // Gated by Engine 1 Compliance Registry
        require(
            identityRegistry.isClearToTrade(msg.sender),
            "TreasuryVault: Investor not KYC verified"
        );

        // 1. Pull stablecoins from investor into Vault treasury
        IERC20(stablecoin).safeTransferFrom(msg.sender, address(this), amount);
        
        totalVaultDeposits += amount;

        // 2. Calculate fractional tokens (adjust scaling depending on your token decimals/price ratio)
        uint256 tokensToTransfer = amount; // e.g. 1:1 ratio representation

        // 3. Transfer fractional property tokens from vault holding to the investor
        IRemzikAssetToken(assetToken).transfer(msg.sender, tokensToTransfer);

        emit StablecoinDeposited(
            msg.sender,
            propertyId,
            stablecoin,
            amount,
            block.timestamp
        );
    }

    function setStablecoinStatus(address stablecoin, bool status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        acceptedStablecoins[stablecoin] = status;
        emit StablecoinUpdated(stablecoin, status);
    }

    function withdrawFunds(address token, address recipient, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).safeTransfer(recipient, amount);
        emit FundsWithdrawn(token, recipient, amount);
    }

    /**
     * @notice Allows an operator (e.g., the backend service) to release fractional property tokens 
     *         from the vault to an investor.
     */
    function releaseTokens(address token, address to, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        require(token == assetToken, "Invalid asset token");
        require(amount > 0, "Amount must be greater than zero");
        IERC20(token).safeTransfer(to, amount);
        emit TokensReleased(token, to, amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}