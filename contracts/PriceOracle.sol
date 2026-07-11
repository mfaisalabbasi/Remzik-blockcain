// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title PriceOracle
 * @notice Provides trading bands for RWA tokens with built-in staleness protection.
 */
contract PriceOracle is AccessControl {
    
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    uint256 public constant STALE_THRESHOLD = 24 hours;

    struct PriceBand {
        uint256 lowerBound;
        uint256 upperBound;
        uint256 updatedAt;
        bool isSet;
    }

    mapping(address => PriceBand) public bands;

    event BandUpdated(address indexed token, uint256 lowerBound, uint256 upperBound, uint256 timestamp);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_MANAGER_ROLE, msg.sender);
    }

    /**
     * @notice Set price bands. Access restricted to Oracle Manager.
     */
    function setPriceBand(address token, uint256 lowerBound, uint256 upperBound) external onlyRole(ORACLE_MANAGER_ROLE) {
        require(token != address(0), "Invalid token");
        require(lowerBound > 0 && lowerBound <= upperBound, "Invalid bounds");
        
        bands[token] = PriceBand(lowerBound, upperBound, block.timestamp, true);
        emit BandUpdated(token, lowerBound, upperBound, block.timestamp);
    }

    /**
     * @notice Retrieves price band with an automatic freshness check.
     * @dev Reverts if data is missing or older than 24 hours.
     */
    function getPriceBand(address token) external view returns (uint256, uint256) {
        PriceBand memory band = bands[token];
        
        require(band.isSet, "Band not set");
        require(block.timestamp - band.updatedAt <= STALE_THRESHOLD, "Oracle data stale");
        
        return (band.lowerBound, band.upperBound);
    }

    /**
     * @notice Bulk update for efficiency in multi-asset environments.
     */
    function setPriceBandsBulk(
        address[] calldata tokens, 
        uint256[] calldata lowerBounds, 
        uint256[] calldata upperBounds
    ) external onlyRole(ORACLE_MANAGER_ROLE) {
        require(tokens.length == lowerBounds.length && tokens.length == upperBounds.length, "Array mismatch");
        
        for (uint256 i = 0; i < tokens.length; i++) {
            bands[tokens[i]] = PriceBand(lowerBounds[i], upperBounds[i], block.timestamp, true);
            emit BandUpdated(tokens[i], lowerBounds[i], upperBounds[i], block.timestamp);
        }
    }
}