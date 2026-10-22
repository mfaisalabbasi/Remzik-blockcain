// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
// Changed from ERC20Votes to standard IERC20 for clean balance checking
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PropertyGovernance is Ownable {
    struct Proposal {
        string description;
        uint256 voteYes;
        uint256 voteNo;
        uint256 deadline;
        bool executed;
        bool exists;
    }

    IERC20 public token;
    address public factory;
    address public treasury;
    
    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event ProposalCreated(uint256 indexed proposalId, string description, uint256 deadline);
    event Voted(uint256 indexed proposalId, address voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId, string action);
    event LiquidationActivated(address indexed tokenAddress);
    event TokenLinked(address indexed tokenAddress);

    constructor(
        address _factory, 
        address _treasury, 
        address _token,
        address _admin
    ) Ownable(_admin) {
        factory = _factory;
        treasury = _treasury;
        if (_token != address(0)) {
            token = IERC20(_token);
        }
    }

    function setToken(address _token) external {
        require(msg.sender == factory || msg.sender == owner(), "Unauthorized");
        require(address(token) == address(0), "Governance: Token already linked");
        token = IERC20(_token);
        emit TokenLinked(_token);
    }

    function createProposal(string memory _description, uint256 _duration) external onlyOwner {
        proposalCount++;
        proposals[proposalCount] = Proposal({
            description: _description,
            voteYes: 0,
            voteNo: 0,
            deadline: block.timestamp + _duration,
            executed: false,
            exists: true
        });
        emit ProposalCreated(proposalCount, _description, block.timestamp + _duration);
    }

    function vote(uint256 _proposalId, bool _support) external {
        Proposal storage p = proposals[_proposalId];
        require(p.exists, "Proposal: Does not exist");
        require(block.timestamp < p.deadline, "Proposal: Voting period ended");
        require(!hasVoted[_proposalId][msg.sender], "Proposal: Already voted");

        // 🛡️ Fintech-Grade Direct Balance Check (1 Token = 1 Vote)
        uint256 weight = token.balanceOf(msg.sender);
        require(weight > 0, "Proposal: No voting power");

        if (_support) p.voteYes += weight;
        else p.voteNo += weight;

        hasVoted[_proposalId][msg.sender] = true;
        emit Voted(_proposalId, msg.sender, _support, weight);
    }

    function executeProposal(uint256 _proposalId) external {
        Proposal storage p = proposals[_proposalId];
        require(p.exists, "Proposal: Does not exist");
        require(block.timestamp >= p.deadline, "Proposal: Still active");
        require(!p.executed, "Proposal: Already executed");
        require(p.voteYes > p.voteNo, "Proposal: Majority not reached");

        p.executed = true;
        
        if (keccak256(bytes(p.description)) == keccak256(bytes("LIQUIDATE"))) {
            require(address(token) != address(0), "Governance: Token not linked");
            (bool success, bytes memory returndata) = address(token).call(abi.encodeWithSignature("activateLiquidation()"));
            if (!success) {
                if (returndata.length > 0) {
                    assembly {
                        let returndata_size := mload(returndata)
                        revert(add(32, returndata), returndata_size)
                    }
                } else {
                    revert("Governance: Liquidation failed");
                }
            }
            emit LiquidationActivated(address(token));
        }
        
        emit ProposalExecuted(_proposalId, p.description);
    }

    function emergencyLiquidate() external onlyOwner {
        require(address(token) != address(0), "Governance: Token not linked");
        
        (bool success, bytes memory returndata) = address(token).call(abi.encodeWithSignature("activateLiquidation()"));
        if (!success) {
            if (returndata.length > 0) {
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert("Governance: Liquidation failed");
            }
        }
        emit LiquidationActivated(address(token));
    }
}