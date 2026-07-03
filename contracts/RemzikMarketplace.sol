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

    // Mapping: listingId => Listing
    mapping(string => Listing) public listings;

    // Events for Backend Indexer
    event ListingCreated(string indexed listingId, address indexed seller, address token, uint256 amount);
    event ListingCancelled(string indexed listingId, address indexed seller);
    event TradeExecuted(string indexed listingId, address indexed seller, address indexed buyer, uint256 amount);

    constructor(address _registry) Ownable(msg.sender) {
        require(_registry != address(0), "Registry cannot be zero address");
        registry = IIdentityRegistry(_registry);
    }

    // --- LISTING LOGIC ---

    /**
     * @notice Allows a verified user to list assets. 
     * Seller must have pre-approved this contract via token.approve().
     */
    function createListing(string calldata listingId, address token, uint256 amount) external nonReentrant {
        require(listings[listingId].seller == address(0), "Listing ID already exists");
        require(registry.isClearToTrade(msg.sender), "Seller not verified");
        require(IERC20(token).allowance(msg.sender, address(this)) >= amount, "Insufficient allowance");
        
        listings[listingId] = Listing(msg.sender, token, amount, true);
        emit ListingCreated(listingId, msg.sender, token, amount);
    }

    /**
     * @notice Allows seller or owner to cancel an active listing.
     */
    function cancelListing(string calldata listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(msg.sender == listing.seller || msg.sender == owner(), "Unauthorized");

        listing.active = false;
        emit ListingCancelled(listingId, listing.seller);
    }

    // --- OWNERSHIP SETTLEMENT LOGIC ---

    /**
     * @notice Atomic settlement called by backend admin.
     * Moves assets directly from Seller to Buyer.
     */
    function settleTrade(
        string calldata listingId, 
        address seller, 
        address buyer
    ) external nonReentrant onlyOwner { 
        Listing storage listing = listings[listingId];
        
        // 1. Validation
        require(listing.active, "Listing not active");
        require(listing.seller == seller, "Seller address mismatch");
        
        // 2. Perform Atomic Transfer
        listing.active = false;
        bool success = IERC20(listing.token).transferFrom(seller, buyer, listing.amount);
        require(success, "Ownership transfer failed");

        // 3. Emit event for backend audit
        emit TradeExecuted(listingId, seller, buyer, listing.amount);
    }

    // --- HELPERS ---

    function isListingActive(string calldata listingId) external view returns (bool) {
        return listings[listingId].active;
    }
}