// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

interface IIdentityRegistry {
    function isClearToTrade(address _user) external view returns (bool);
}

contract RemzikAssetToken is ERC20, AccessControl {
    bytes32 public constant COMPLIANCE_BYPASS_ROLE = keccak256("COMPLIANCE_BYPASS_ROLE");
    IIdentityRegistry public immutable registry;
    string public metadataHash;

    event MetadataUpdated(string newHash);

    constructor(
        string memory name,
        string memory symbol,
        uint256 supply,
        string memory _metadataHash,
        address _registry,
        address _treasury
    ) ERC20(name, symbol) {
        registry = IIdentityRegistry(_registry);
        metadataHash = _metadataHash;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(COMPLIANCE_BYPASS_ROLE, _treasury);
        
        _mint(_treasury, supply);
    }

    function setMetadataHash(string memory newHash) external onlyRole(DEFAULT_ADMIN_ROLE) {
        metadataHash = newHash;
        emit MetadataUpdated(newHash);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && !hasRole(COMPLIANCE_BYPASS_ROLE, from)) {
            require(registry.isClearToTrade(from), "ComplianceFailed: Sender");
        }
        
        if (to != address(0) && !hasRole(COMPLIANCE_BYPASS_ROLE, to)) {
            require(registry.isClearToTrade(to), "ComplianceFailed: Receiver");
        }
        
        super._update(from, to, value);
    }
}