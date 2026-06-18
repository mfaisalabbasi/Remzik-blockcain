// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RemzikAssetToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AssetFactory is Ownable {
    event AssetTokenDeployed(address indexed tokenAddress, string name, string symbol, address indexed treasury);
    
    address public immutable registry;

    constructor(address _registry) Ownable(msg.sender) {
        registry = _registry;
    }

    function deployAsset(
        string memory name,
        string memory symbol,
        uint256 supply,
        string memory metadataHash,
        address treasury
    ) external onlyOwner returns (address) {
        RemzikAssetToken newToken = new RemzikAssetToken(
            name,
            symbol,
            supply,
            metadataHash,
            registry,
            treasury
        );
        
        emit AssetTokenDeployed(address(newToken), name, symbol, treasury);
        
        return address(newToken);
    }
}