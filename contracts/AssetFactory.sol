// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

interface ITokenDeployer {
    function deployToken(bytes memory creationCode, bytes memory constructorArgs) external returns (address);
}

interface IGovDeployer {
    function deployGovernance(bytes memory creationCode, bytes memory constructorArgs) external returns (address);
}

interface IRemzikAssetToken {
    function grantRole(bytes32 role, address account) external;
    function GOVERNANCE_ROLE() external view returns (bytes32);
    function RECOVERY_ROLE() external view returns (bytes32);
    function COMPLIANCE_BYPASS_ROLE() external view returns (bytes32);
}

interface IPropertyGovernance {
    function transferOwnership(address newOwner) external;
}

contract AssetFactoryUpgradeable is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    bytes32 public constant ASSET_DEPLOYER_ROLE = keccak256("ASSET_DEPLOYER_ROLE");

    event AssetPodDeployed(
        address indexed tokenAddress,
        address indexed treasuryAddress,
        address indexed governanceAddress,
        string name
    );

    // State variables (Maintain order for storage safety)
    address public registry;
    address public recoveryManager;
    address public tokenDeployer;
    address public govDeployer;
    address public treasuryVaultImplementation;
    
    // Default stablecoin address to auto-whitelist on newly deployed property vaults
    address public defaultStablecoin;
    
    // Marketplace address to auto-grant compliance bypass role on newly deployed asset tokens
    address public marketplace;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _registry,
        address _recoveryManager,
        address _tokenDeployer,
        address _govDeployer,
        address initialAdmin
    ) external initializer {
        require(initialAdmin != address(0), "Invalid admin");
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ASSET_DEPLOYER_ROLE, initialAdmin);

        registry = _registry;
        recoveryManager = _recoveryManager;
        tokenDeployer = _tokenDeployer;
        govDeployer = _govDeployer;
    }

    function setDeployers(address _tokenDeployer, address _govDeployer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        tokenDeployer = _tokenDeployer;
        govDeployer = _govDeployer;
    }

    function setTreasuryVaultImplementation(address _treasuryVaultImplementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasuryVaultImplementation != address(0), "Invalid address");
        treasuryVaultImplementation = _treasuryVaultImplementation;
    }

    function setDefaultStablecoin(address _defaultStablecoin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        defaultStablecoin = _defaultStablecoin;
    }

    function setMarketplace(address _marketplace) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_marketplace != address(0), "Invalid marketplace address");
        marketplace = _marketplace;
    }

    function deployAssetWithBytecode(
        bytes memory tokenCreationCode,
        bytes memory tokenArgs,
        bytes memory govCreationCode,
        bytes memory govArgs,
        string memory name,
        bytes32 propertyId,
        address admin
    ) external onlyRole(ASSET_DEPLOYER_ROLE) returns (address, address, address) {

        // 1. Deploy Token dynamically
        address newToken = ITokenDeployer(tokenDeployer).deployToken(tokenCreationCode, tokenArgs);

        // 2. Deploy Governance dynamically
        address newGovernance = IGovDeployer(govDeployer).deployGovernance(govCreationCode, govArgs);

        // 3. Deploy Engine 2: TreasuryVault Proxy dynamically (Atomically passing 5 parameters including defaultStablecoin)
        address deployedTreasury = address(0);
        if (treasuryVaultImplementation != address(0)) {
            bytes memory vaultInitData = abi.encodeWithSignature(
                "initialize(address,address,bytes32,address,address)", 
                registry,
                admin,
                propertyId,
                newToken,
                defaultStablecoin 
            );
            ERC1967Proxy vaultProxy = new ERC1967Proxy(treasuryVaultImplementation, vaultInitData);
            deployedTreasury = address(vaultProxy);
        }

        // 4. BONDING: Grant Governance role to the PropertyGovernance contract
        bytes32 govRole = IRemzikAssetToken(newToken).GOVERNANCE_ROLE();
        IRemzikAssetToken(newToken).grantRole(govRole, newGovernance);

        // 5. BONDING: Automatically grant RECOVERY_ROLE to the RecoveryManager contract
        bytes32 recoveryRole = IRemzikAssetToken(newToken).RECOVERY_ROLE();
        IRemzikAssetToken(newToken).grantRole(recoveryRole, recoveryManager);

        // 6. BONDING: Automatically grant COMPLIANCE_BYPASS_ROLE to the Marketplace contract
        if (marketplace != address(0)) {
            bytes32 bypassRole = IRemzikAssetToken(newToken).COMPLIANCE_BYPASS_ROLE();
            IRemzikAssetToken(newToken).grantRole(bypassRole, marketplace);
        }

        emit AssetPodDeployed(newToken, deployedTreasury, newGovernance, name);

        return (newToken, deployedTreasury, newGovernance);
    }

    function transferGovernanceOwnership(address govAddress, address newOwner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IPropertyGovernance(govAddress).transferOwnership(newOwner);
    }

    // Required by UUPS standard to authorize code upgrades
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // Storage gap for future upgrades (adjusted slot allocation down by 1 to accommodate the new marketplace state variable)
    uint256[45] private __gap;
}