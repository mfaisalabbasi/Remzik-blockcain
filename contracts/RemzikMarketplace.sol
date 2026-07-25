// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IIdentityRegistry {
    function isClearToTrade(address account) external view returns (bool);
}

interface IPriceOracle {
    function getPriceBand(address token) external view returns (uint256, uint256);
}

/**
 * @title RemzikMarketplace
 * @notice Production version: Includes Balance Checks + Allowance Gating + Price Banding + Strict Liquidation Shield.
 */
contract RemzikMarketplace is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IIdentityRegistry public immutable registry;
    IPriceOracle public priceOracle;

    struct Listing {
        address seller;
        address token;
        uint256 amount;
        bool active;
    }

    mapping(string => Listing) public listings;

    event ListingCreated(string indexed listingId, address indexed seller, address token, uint256 amount);
    event ListingCancelled(string indexed listingId, address indexed seller);
    event TradeExecuted(string indexed listingId, address indexed seller, address indexed buyer, uint256 amount);

    constructor(address _registry, address _priceOracle) Ownable(msg.sender) {
        require(_registry != address(0), "Registry cannot be zero address");
        require(_priceOracle != address(0), "Oracle cannot be zero address");
        registry = IIdentityRegistry(_registry);
        priceOracle = IPriceOracle(_priceOracle);
    }

    // --- INTERNAL GUARDRAILS ---
    function _checkPriceBand(address token, uint256 totalTradePrice, uint256 amount) internal view {
        (uint256 minPerToken, uint256 maxPerToken) = priceOracle.getPriceBand(token);
        require(amount > 0, "Invalid amount");

        uint256 pricePerToken = (totalTradePrice * 1e18) / amount; 
        uint256 buffer = minPerToken / 100; // 1% buffer
        
        uint256 effectiveMin = (minPerToken > buffer) ? (minPerToken - buffer) : 0;
        uint256 effectiveMax = maxPerToken + buffer;
        
        require(pricePerToken >= effectiveMin && pricePerToken <= effectiveMax, "Price outside permitted band");
    }

    // --- LISTING LOGIC ---
    function createListing(string calldata listingId, address token, uint256 amount) external nonReentrant {
        require(listings[listingId].seller == address(0), "Listing exists");
        require(registry.isClearToTrade(msg.sender), "Seller not verified");
        
        // SECURITY UPDATE: Check actual token balance to prevent listing what you don't own
        require(IERC20(token).balanceOf(msg.sender) >= amount, "Insufficient token balance");
        
        // Verify allowance (supports MaxUint256)
        require(IERC20(token).allowance(msg.sender, address(this)) >= amount, "Insufficient allowance");
        
        listings[listingId] = Listing(msg.sender, token, amount, true);
        emit ListingCreated(listingId, msg.sender, token, amount);
    }

    function cancelListing(string calldata listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing inactive");
        require(msg.sender == listing.seller || msg.sender == owner(), "Unauthorized");

        listing.active = false;
        emit ListingCancelled(listingId, listing.seller);
    }

    // --- SETTLEMENT LOGIC ---
    function settleTrade(
        string calldata listingId, 
        address seller, 
        address buyer,
        uint256 tradePrice 
    ) external nonReentrant { 
        Listing storage listing = listings[listingId];
        
        require(listing.active, "Listing inactive");
        require(listing.seller == seller, "Seller mismatch");
        require(buyer != address(0), "Invalid buyer");
        
        // 🛡️ HARD GUARD: Strict verification to completely block secondary trades during liquidation/pause
        (bool success, bytes memory data) = listing.token.staticcall(abi.encodeWithSignature("paused()"));
        require(success, "Marketplace: Failed to check token pause status");
        bool isPaused = abi.decode(data, (bool));
        require(!isPaused, "Marketplace: Token is paused due to emergency liquidation");
        
        _checkPriceBand(listing.token, tradePrice, listing.amount); 
        
        listing.active = false;
        
        // Transfer from seller to buyer
        IERC20(listing.token).safeTransferFrom(seller, buyer, listing.amount);

        emit TradeExecuted(listingId, seller, buyer, listing.amount);
    }

    // --- UTILS ---
    function getListing(string calldata listingId) external view returns (Listing memory) {
        return listings[listingId];
    }

    function updatePriceOracle(address _newOracle) external onlyOwner {
        require(_newOracle != address(0), "Invalid address");
        priceOracle = IPriceOracle(_newOracle);
    }
}