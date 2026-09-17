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
    function revokeRole(bytes32 role, address account) external;
    function mint(address to, uint256 amount) external;
    function GOVERNANCE_ROLE() external view returns (bytes32);
    function RECOVERY_ROLE() external view returns (bytes32);
    function COMPLIANCE_BYPASS_ROLE() external view returns (bytes32);
    function MINTER_ROLE() external view returns (bytes32);
}

interface IPropertyGovernance {
    function transferOwnership(address newOwner) external;
    function setToken(address _token) external;
}

contract AssetFactoryUpgradeable is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    bytes32 public constant ASSET_DEPLOYER_ROLE = keccak256("ASSET_DEPLOYER_ROLE");

    event AssetPodDeployed(
        address indexed tokenAddress,
        address indexed treasuryAddress,
        address indexed governanceAddress,
        string name
    );

    address public registry;
    address public recoveryManager;
    address public tokenDeployer;
    address public govDeployer;
    address public treasuryVaultImplementation;
    address public defaultStablecoin;
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

    /**
     * @notice Dynamically deploys an asset pod. 
     */
    function deployAssetWithBytecode(
        bytes memory tokenCreationCode,
        bytes memory tokenArgs,
        bytes memory govCreationCode,
        bytes memory govArgs,
        string memory name,
        uint256 totalSharesWei,
        bytes32 propertyId,
        address admin
    ) external onlyRole(ASSET_DEPLOYER_ROLE) returns (address, address, address) {

        // 1. Deploy Governance first so its address is available
        address newGovernance = IGovDeployer(govDeployer).deployGovernance(govCreationCode, govArgs);

        // 2. Deploy Token dynamically
        address newToken = ITokenDeployer(tokenDeployer).deployToken(tokenCreationCode, tokenArgs);

        // 3. Deploy Engine 2: TreasuryVault Proxy dynamically & Auto-Whitelist on Registry
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

            // 🛡️ COMPLIANCE FIX: Call registerTreasuryByFactory which checks ASSET_FACTORY_ROLE
            (bool success, ) = registry.call(
                abi.encodeWithSignature("registerTreasuryByFactory(address)", deployedTreasury)
            );
            require(success, "Factory: Failed to auto-whitelist treasury vault");
        }

        // 4. ATOMIC MINTING: Mint total supply directly into the deployed Treasury Vault proxy
        if (deployedTreasury != address(0) && totalSharesWei > 0) {
            IRemzikAssetToken(newToken).mint(deployedTreasury, totalSharesWei);
        }

        // 5. SECURITY LOCKDOWN: Revoke factory's temporary MINTER_ROLE safely using factory's temporary ADMIN role
        bytes32 minterRole = IRemzikAssetToken(newToken).MINTER_ROLE();
        IRemzikAssetToken(newToken).revokeRole(minterRole, address(this));

        // 6. BONDING: Grant Governance role to the PropertyGovernance contract
        bytes32 govRole = IRemzikAssetToken(newToken).GOVERNANCE_ROLE();
        IRemzikAssetToken(newToken).grantRole(govRole, newGovernance);

        // 7. BONDING: Automatically grant RECOVERY_ROLE to the RecoveryManager contract
        bytes32 recoveryRole = IRemzikAssetToken(newToken).RECOVERY_ROLE();
        IRemzikAssetToken(newToken).grantRole(recoveryRole, recoveryManager);

        // 8. BONDING: Automatically grant COMPLIANCE_BYPASS_ROLE to the Marketplace contract
        if (marketplace != address(0)) {
            bytes32 bypassRole = IRemzikAssetToken(newToken).COMPLIANCE_BYPASS_ROLE();
            IRemzikAssetToken(newToken).grantRole(bypassRole, marketplace);
        }

        // 9. BONDING: Link the deployed token address back to PropertyGovernance so voting/liquidation works properly
        IPropertyGovernance(newGovernance).setToken(newToken);

        emit AssetPodDeployed(newToken, deployedTreasury, newGovernance, name);

        return (newToken, deployedTreasury, newGovernance);
    }

    function transferGovernanceOwnership(address govAddress, address newOwner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IPropertyGovernance(govAddress).transferOwnership(newOwner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    uint256[45] private __gap;
}