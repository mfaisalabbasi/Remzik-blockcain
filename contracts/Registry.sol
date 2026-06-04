// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Registry {
    address public owner;
    
    constructor() {
        owner = msg.sender;
    }
    
    // You can add logic here to store addresses later
}