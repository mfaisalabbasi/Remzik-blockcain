// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IIdentityRegistry {
    function isClearToTrade(address account) external view returns (bool);
}

contract RemzikMarketplace is Ownable, ReentrancyGuard {
    IIdentityRegistry public immutable registry;

    struct Listing {
        address seller;
        address token;
        uint256 amount;
        bool active;
    }

    mapping(string => Listing) public listings;

    event ListingCreated(string indexed listingId, address indexed seller, address token, uint256 amount);
    event ListingCancelled(string indexed listingId, address indexed seller);
    event TradeExecuted(bytes32 indexed txId, address indexed seller, address indexed buyer, address token, uint256 amount, uint256 price);

    constructor(address _registry) Ownable(msg.sender) {
        require(_registry != address(0), "Registry cannot be zero address");
        registry = IIdentityRegistry(_registry);
    }

    /**
     * @dev Sellers list their own assets directly. Backend no longer manages nonces.
     */
    function createListing(
        string calldata listingId, 
        address token, 
        uint256 amount
    ) external nonReentrant {
        require(listings[listingId].seller == address(0), "Listing ID already exists");
        require(registry.isClearToTrade(msg.sender), "Seller not verified in registry");
        require(IERC20(token).allowance(msg.sender, address(this)) >= amount, "Insufficient allowance");
        
        listings[listingId] = Listing(msg.sender, token, amount, true);
        
        emit ListingCreated(listingId, msg.sender, token, amount);
    }

    function cancelListing(string calldata listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing is not active");
        require(msg.sender == listing.seller || msg.sender == owner(), "Unauthorized");

        listing.active = false;
        emit ListingCancelled(listingId, listing.seller);
    }

    /**
     * @dev Buyers execute trades directly.
     */
    function executeTrade(
        string calldata listingId, 
        uint256 price
    ) external nonReentrant returns (bytes32) {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        
        address seller = listing.seller;
        address token = listing.token;
        uint256 amount = listing.amount;

        listing.active = false; 

        // Execute transfer from seller to buyer (msg.sender)
        bool success = IERC20(token).transferFrom(seller, msg.sender, amount);
        require(success, "Token transfer failed");

        bytes32 txId = keccak256(abi.encodePacked(listingId, msg.sender, block.timestamp));
        emit TradeExecuted(txId, seller, msg.sender, token, amount, price);
        
        return txId;
    }

    function isListingActive(string calldata listingId) external view returns (bool) {
        return listings[listingId].active;
    }
}