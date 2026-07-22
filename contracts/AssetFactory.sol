// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

interface ITokenDeployer {
    function deployToken(bytes memory creationCode, bytes memory constructorArgs) external returns (address);
}

interface IGovDeployer {
    function deployGovernance(bytes memory creationCode, bytes memory constructorArgs) external returns (address);
}

interface IRemzikAssetToken {
    function grantRole(bytes32 role, address account) external;
    function GOVERNANCE_ROLE() external view returns (bytes32);
}

interface IPropertyGovernance {
    function transferOwnership(address newOwner) external;
}

contract AssetFactory is Ownable {
    event AssetPodDeployed(
        address indexed tokenAddress,
        address indexed treasuryAddress,
        address indexed governanceAddress,
        string name
    );
    
    address public immutable registry;
    address public tokenDeployer;
    address public govDeployer;

    constructor(
        address _registry,
        address _tokenDeployer,
        address _govDeployer
    ) Ownable(msg.sender) {
        registry = _registry;
        tokenDeployer = _tokenDeployer;
        govDeployer = _govDeployer;
    }

    function setDeployers(address _tokenDeployer, address _govDeployer) external onlyOwner {
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
    ) external onlyOwner returns (address, address, address) {
        
        // Note: Ensure your backend encoding includes address(this) as the 7th parameter (admin) 
        // for the token constructor so the factory receives DEFAULT_ADMIN_ROLE.
        
        // 1. Deploy Token dynamically
        address newToken = ITokenDeployer(tokenDeployer).deployToken(tokenCreationCode, tokenArgs);
        
        // 2. Deploy Governance dynamically using creation code and args
        address newGovernance = IGovDeployer(govDeployer).deployGovernance(govCreationCode, govArgs);
        
        // 3. BONDING: Grant Governance role (Now works because factory is admin)
        IRemzikAssetToken(newToken).grantRole(
            IRemzikAssetToken(newToken).GOVERNANCE_ROLE(), 
            newGovernance
        );
        
        emit AssetPodDeployed(newToken, treasury, newGovernance, name);
        
        return (newToken, treasury, newGovernance);
    }

    function transferGovernanceOwnership(address govAddress, address newOwner) external onlyOwner {
        IPropertyGovernance(govAddress).transferOwnership(newOwner);
    }
}