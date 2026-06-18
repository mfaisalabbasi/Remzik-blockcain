// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract RemzikIdentityRegistry {
    address public owner;

    struct IdentityState {
        bool isVerified;
        bool isFrozen;
    }

    mapping(address => IdentityState) private _registry;

    error UnauthorizedCaller(address caller);
    error InvalidAddress();

    event IdentityUpdated(address indexed investor, bool isVerified, address indexed authorizedBy);
    event IdentityFreezeToggled(address indexed investor, bool isFrozen, address indexed authorizedBy);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        if (msg.sender != owner) revert UnauthorizedCaller(msg.sender);
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function registerIdentity(address investor, bool status) external onlyOwner {
        if (investor == address(0)) revert InvalidAddress();
        _registry[investor].isVerified = status;
        emit IdentityUpdated(investor, status, msg.sender);
    }

    function batchRegisterIdentity(address[] calldata investors, bool status) external onlyOwner {
        for (uint256 i = 0; i < investors.length; i++) {
            if (investors[i] == address(0)) revert InvalidAddress();
            _registry[investors[i]].isVerified = status;
            emit IdentityUpdated(investors[i], status, msg.sender);
        }
    }

    function toggleFreeze(address investor, bool freezeStatus) external onlyOwner {
        if (investor == address(0)) revert InvalidAddress();
        _registry[investor].isFrozen = freezeStatus;
        emit IdentityFreezeToggled(investor, freezeStatus, msg.sender);
    }

    function isClearToTrade(address investor) external view returns (bool) {
        IdentityState memory state = _registry[investor];
        if (state.isFrozen) return false;
        return state.isVerified;
    }

    function getIdentityState(address investor) external view returns (bool verified, bool frozen) {
        IdentityState memory state = _registry[investor];
        return (state.isVerified, state.isFrozen);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}