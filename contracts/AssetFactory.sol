// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RemzikAssetToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AssetFactory is Ownable {
    event AssetTokenDeployed(address indexed tokenAddress, string title);
    address public immutable registry;

    constructor(address _registry) Ownable(msg.sender) {
        registry = _registry;
    }

    // This function must accept 5 arguments, and then pass 6 to the Token
    function deployAsset(
        string memory name,
        string memory symbol,
        uint256 supply,
        string memory metadataHash,
        address treasury
    ) external onlyOwner returns (address) {
        // Here we pass 6 arguments:
        // (1) name, (2) symbol, (3) supply, (4) metadataHash, (5) registry, (6) treasury
        RemzikAssetToken newToken = new RemzikAssetToken(
            name,
            symbol,
            supply,
            metadataHash,
            registry,
            treasury
        );
        
        emit AssetTokenDeployed(address(newToken), name);
        return address(newToken);
    }
}