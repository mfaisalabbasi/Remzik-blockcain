// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockUSDC
 * @notice A mock ERC-20 stablecoin with 6 decimals for testing Remzik RWA vaults locally.
 */
contract MockUSDC is ERC20, Ownable {
    constructor() ERC20("USD Coin", "USDC") Ownable(msg.sender) {}

    /**
     * @notice Public mint function to fund test wallets on Hardhat/testnets.
     * @param to The recipient address.
     * @param amount The amount to mint (adjusted for decimals).
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Enforces 6 decimals to match real-world Circle USDC standards.
     */
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}