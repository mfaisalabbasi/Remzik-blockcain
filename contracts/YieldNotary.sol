// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract YieldNotary {
    address public owner;
    event YieldRecorded(bytes32 indexed batchId, address indexed property, uint256 amount, uint256 timestamp);

    constructor() { owner = msg.sender; }

    function recordYield(bytes32 _batchId, address _property, uint256 _amount) external {
        require(msg.sender == owner, "Only admin");
        emit YieldRecorded(_batchId, _property, _amount, block.timestamp);
    }
}