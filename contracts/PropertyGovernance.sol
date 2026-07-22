// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/**
 * @title PropertyGovernance
 * @dev Manages operational proposals and triggers emergency liquidation for an asset pod.
 */
contract PropertyGovernance is Ownable {
    struct Proposal {
        string description;
        uint256 voteYes;
        uint256 voteNo;
        uint256 deadline;
        bool executed;
        bool exists;
    }

    ERC20Votes public token;
    address public factory;
    address public treasury;
    
    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event ProposalCreated(uint256 indexed proposalId, string description, uint256 deadline);
    event Voted(uint256 indexed proposalId, address voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId, string action);
    event LiquidationActivated(address indexed tokenAddress);

    constructor(
        address _factory, 
        address _treasury, 
        address _token,
        address _admin
    ) Ownable(_admin) {
        factory = _factory;
        treasury = _treasury;
        token = ERC20Votes(_token);
    }

    // 1. Create a proposal (e.g., "BUYOUT", "RENOVATION")
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

    // 2. Investors vote using their delegated token balance
    function vote(uint256 _proposalId, bool _support) external {
        Proposal storage p = proposals[_proposalId];
        require(p.exists, "Proposal: Does not exist");
        require(block.timestamp < p.deadline, "Proposal: Voting period ended");
        require(!hasVoted[_proposalId][msg.sender], "Proposal: Already voted");

        uint256 weight = token.getVotes(msg.sender);
        require(weight > 0, "Proposal: No voting power");

        if (_support) p.voteYes += weight;
        else p.voteNo += weight;

        hasVoted[_proposalId][msg.sender] = true;
        emit Voted(_proposalId, msg.sender, _support, weight);
    }

    // 3. Execute action based on majority
    function executeProposal(uint256 _proposalId) external onlyOwner {
        Proposal storage p = proposals[_proposalId];
        require(block.timestamp >= p.deadline, "Proposal: Still active");
        require(!p.executed, "Proposal: Already executed");
        require(p.voteYes > p.voteNo, "Proposal: Majority not reached");

        p.executed = true;
        
        // If it's a liquidation proposal, trigger the token kill-switch
        if (keccak256(bytes(p.description)) == keccak256(bytes("LIQUIDATE"))) {
            // This requires the contract to have GOVERNANCE_ROLE on the Token
            (bool success, ) = address(token).call(abi.encodeWithSignature("activateLiquidation()"));
            require(success, "Governance: Liquidation failed");
            emit LiquidationActivated(address(token));
        }
        
        emit ProposalExecuted(_proposalId, p.description);
    }
}