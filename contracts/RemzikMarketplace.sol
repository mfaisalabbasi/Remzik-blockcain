// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IIdentityRegistry {
    function isClearToTrade(address account) external view returns (bool);
}

interface IPriceOracle {
    function getPriceBand(address token) external view returns (uint256, uint256);
}

/**
 * @title RemzikMarketplace
 * @notice UUPS Upgradeable production version with fixed-price escrow enforcement, payment whitelisting, and atomic settlement.
 */
contract RemzikMarketplace is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    IIdentityRegistry public registry;
    IPriceOracle public priceOracle;

    struct Listing {
        address seller;
        address token;          // Asset token contract address
        address paymentToken;   // Accepted payment token (e.g., MockUSDC)
        uint256 amount;         // Number of tokens listed
        uint256 pricePerUnit;   // Fixed price per token unit (scaled to payment token decimals)
        bool active;
    }

    mapping(string => Listing) public listings;
    mapping(address => bool) public acceptedPaymentTokens;

    // Custom reentrancy guard states for upgradeable safety
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    event ListingCreated(
        string indexed listingId, 
        address indexed seller, 
        address token, 
        address paymentToken, 
        uint256 amount, 
        uint256 pricePerUnit
    );
    event ListingCancelled(string indexed listingId, address indexed seller);
    event TradeExecuted(
        string indexed listingId, 
        address indexed seller, 
        address indexed buyer, 
        address paymentToken,
        uint256 paymentAmount,
        uint256 tokenAmount
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _registry, 
        address _priceOracle,
        address initialOwner
    ) external initializer {
        require(_registry != address(0), "Registry cannot be zero address");
        require(_priceOracle != address(0), "Oracle cannot be zero address");

        __Ownable_init(initialOwner);
        _status = _NOT_ENTERED;

        registry = IIdentityRegistry(_registry);
        priceOracle = IPriceOracle(_priceOracle);
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    function setPaymentTokenStatus(address token, bool status) external onlyOwner {
        require(token != address(0), "Invalid token address");
        acceptedPaymentTokens[token] = status;
    }

   function _checkPriceBand(address token, uint256 totalTradePrice, uint256 amount) internal view {
        (uint256 minPerToken, uint256 maxPerToken) = priceOracle.getPriceBand(token);
        require(amount > 0, "Invalid amount");

        // 🛡️ Fix: Remove the extra * 1e18 multiplication.
        // totalTradePrice is in 6 decimals (USDC). Multiplying by 1e12 converts it to 18 decimals,
        // which matches the 18-decimal scale set by OracleService.
        uint256 pricePerToken = (totalTradePrice * 1e12) / amount; 
        
        uint256 buffer = minPerToken / 100; // 1% buffer
        uint256 effectiveMin = (minPerToken > buffer) ? (minPerToken - buffer) : 0;
        uint256 effectiveMax = maxPerToken + buffer;
        
        require(pricePerToken >= effectiveMin && pricePerToken <= effectiveMax, "Price outside permitted band");
    }

    // --- LISTING LOGIC (WITH ESCROW) ---
    function createListing(
        string calldata listingId, 
        address token, 
        address paymentToken,
        uint256 amount, 
        uint256 pricePerUnit
    ) external nonReentrant {
        require(listings[listingId].seller == address(0), "Listing already exists");
        require(registry.isClearToTrade(msg.sender), "Seller not verified");
        require(acceptedPaymentTokens[paymentToken], "Payment token not accepted");
        require(amount > 0, "Amount must be greater than zero");
        require(pricePerUnit > 0, "Price must be greater than zero");

        // Transfer property tokens from seller into marketplace escrow contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        listings[listingId] = Listing({
            seller: msg.sender,
            token: token,
            paymentToken: paymentToken,
            amount: amount,
            pricePerUnit: pricePerUnit,
            active: true
        });

        emit ListingCreated(listingId, msg.sender, token, paymentToken, amount, pricePerUnit);
    }

    // --- CANCELLATION LOGIC (REFUND FROM ESCROW) ---
    function cancelListing(string calldata listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing inactive");
        require(msg.sender == listing.seller || msg.sender == owner(), "Unauthorized");

        listing.active = false;

        // Return escrowed tokens back to the seller
        IERC20(listing.token).safeTransfer(listing.seller, listing.amount);

        emit ListingCancelled(listingId, listing.seller);
    }

    // --- ATOMIC ON-CHAIN SETTLEMENT ---
    function executeOnChainTrade(
        string calldata listingId,
        uint256 purchaseAmount
    ) external nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.active, "Listing inactive");
        require(msg.sender != listing.seller, "Seller cannot buy own listing");
        require(purchaseAmount > 0 && purchaseAmount <= listing.amount, "Invalid purchase amount");
        require(registry.isClearToTrade(msg.sender), "Buyer not verified");
        require(registry.isClearToTrade(listing.seller), "Seller not verified");

        // Emergency Liquidation Shield check on asset token
        (bool success, bytes memory data) = listing.token.staticcall(abi.encodeWithSignature("paused()"));
        require(success, "Marketplace: Failed to check token pause status");
        bool isPaused = abi.decode(data, (bool));
        require(!isPaused, "Marketplace: Token is paused due to emergency liquidation");

        uint256 totalPayment = purchaseAmount * listing.pricePerUnit;

        // Verify price against Oracle bands
        _checkPriceBand(listing.token, totalPayment, purchaseAmount);

        if (purchaseAmount == listing.amount) {
            listing.active = false;
        } else {
            listing.amount -= purchaseAmount;
        }

        // 1. Transfer Payment Token from Buyer to Seller
        IERC20(listing.paymentToken).safeTransferFrom(msg.sender, listing.seller, totalPayment);

        // 2. Release Escrowed Asset Tokens from Marketplace to Buyer
        IERC20(listing.token).safeTransfer(msg.sender, purchaseAmount);

        emit TradeExecuted(
            listingId,
            listing.seller,
            msg.sender,
            listing.paymentToken,
            totalPayment,
            purchaseAmount
        );
    }

    function getListing(string calldata listingId) external view returns (Listing memory) {
        return listings[listingId];
    }

    function updatePriceOracle(address _newOracle) external onlyOwner {
        require(_newOracle != address(0), "Invalid address");
        priceOracle = IPriceOracle(_newOracle);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    uint256[47] private __gap;

    // --- OFF-CHAIN ESCROW ON-CHAIN RELEASE ---
    function releaseOffChainEscrowTrade(
        string calldata listingId,
        address buyer,
        uint256 tokenAmount
    ) external onlyOwner nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing inactive");
        require(tokenAmount > 0 && tokenAmount <= listing.amount, "Invalid token amount");

        if (tokenAmount == listing.amount) {
            listing.active = false;
        } else {
            listing.amount -= tokenAmount;
        }

        // Release escrowed asset tokens straight to the buyer (Payment was handled off-chain)
        IERC20(listing.token).safeTransfer(buyer, tokenAmount);

        emit TradeExecuted(
            listingId,
            listing.seller,
            buyer,
            address(0),
            0,
            tokenAmount
        );
    }
}