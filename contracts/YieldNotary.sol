// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract YieldNotary is Ownable, ReentrancyGuard {
    
    IERC20 public immutable stablecoin;
    
    // batchId => Merkle Root
    mapping(bytes32 => bytes32) public batchMerkleRoots;
    
    // batchId => account => claimed status
    mapping(bytes32 => mapping(address => bool)) public isClaimed;

    event YieldRecorded(bytes32 indexed batchId, address indexed property, uint256 amount, uint256 timestamp);
    event YieldBatchMerkleRecorded(bytes32 indexed batchId, address indexed property, bytes32 merkleRoot, uint256 totalAmount, uint256 timestamp);
    event YieldClaimed(bytes32 indexed batchId, address indexed account, uint256 amount, uint256 timestamp);

    constructor(address _initialOwner, address _stablecoin) Ownable(_initialOwner) { 
        require(_stablecoin != address(0), "Invalid stablecoin address");
        stablecoin = IERC20(_stablecoin);
    }

    function recordYield(bytes32 _batchId, address _property, uint256 _amount) external onlyOwner {
        require(_property != address(0), "Invalid property address");
        emit YieldRecorded(_batchId, _property, _amount, block.timestamp);
    }

    function recordYieldWithMerkle(
        bytes32 _batchId, 
        address _property, 
        bytes32 _merkleRoot, 
        uint256 _totalAmount
    ) external onlyOwner {
        require(_property != address(0), "Invalid property address");
        require(_merkleRoot != bytes32(0), "Invalid Merkle root");
        require(_totalAmount > 0, "Invalid total amount");
        
        batchMerkleRoots[_batchId] = _merkleRoot;
        
        emit YieldBatchMerkleRecorded(_batchId, _property, _merkleRoot, _totalAmount, block.timestamp);
    }

    // Trustless claim function matching OpenZeppelin's StandardMerkleTree leaf format: abi.encode(address, uint256)
    function claimYield(
        bytes32 _batchId,
        address _account,
        uint256 _amount,
        bytes32[] calldata _merkleProof
    ) external nonReentrant {
        require(!isClaimed[_batchId][_account], "Yield already claimed");
        
        bytes32 root = batchMerkleRoots[_batchId];
        require(root != bytes32(0), "Invalid or inactive batch root");

        // Match OpenZeppelin StandardMerkleTree leaf standard format ['address', 'uint256']
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(_account, _amount))));
        
        // Handle both single-item trees (empty proof) and multi-leaf trees securely
        if (_merkleProof.length == 0) {
            require(leaf == root, "Invalid Merkle root match");
        } else {
            require(MerkleProof.verify(_merkleProof, root, leaf), "Invalid Merkle proof");
        }

        isClaimed[_batchId][_account] = true;

        bool success = stablecoin.transfer(_account, _amount);
        require(success, "Token transfer failed");

        emit YieldClaimed(_batchId, _account, _amount, block.timestamp);
    }
}