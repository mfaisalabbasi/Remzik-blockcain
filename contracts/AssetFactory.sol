// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
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

    function deployAssetWithBytecode(
        bytes memory tokenCreationCode,
        bytes memory tokenArgs,
        bytes memory govCreationCode,
        bytes memory govArgs,
        string memory name,
        address treasury,
        address /* admin */
    ) external onlyRole(ASSET_DEPLOYER_ROLE) returns (address, address, address) {

        // 1. Deploy Token dynamically
        address newToken = ITokenDeployer(tokenDeployer).deployToken(tokenCreationCode, tokenArgs);

        // 2. Deploy Governance dynamically
        address newGovernance = IGovDeployer(govDeployer).deployGovernance(govCreationCode, govArgs);

        // 3. BONDING: Grant Governance role to the PropertyGovernance contract
        bytes32 govRole = IRemzikAssetToken(newToken).GOVERNANCE_ROLE();
        IRemzikAssetToken(newToken).grantRole(govRole, newGovernance);

        // 4. BONDING: Automatically grant RECOVERY_ROLE to the RecoveryManager contract
        bytes32 recoveryRole = IRemzikAssetToken(newToken).RECOVERY_ROLE();
        IRemzikAssetToken(newToken).grantRole(recoveryRole, recoveryManager);

        emit AssetPodDeployed(newToken, treasury, newGovernance, name);

        return (newToken, treasury, newGovernance);
    }

    function transferGovernanceOwnership(address govAddress, address newOwner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IPropertyGovernance(govAddress).transferOwnership(newOwner);
    }

    // Required by UUPS standard to authorize code upgrades
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // Storage gap for future upgrades
    uint256[48] private __gap;
}