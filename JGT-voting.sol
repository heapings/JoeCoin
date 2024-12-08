// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Governance is ReentrancyGuard {
    JGTToken public immutable token;
    
    struct Proposal {
        address proposer;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        bool executed;
        mapping(address => bool) hasVoted;
    }
    
    struct ProposalInfo {
        address proposer;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        bool executed;
    }
    
    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;
    
    uint256 public constant VOTING_DELAY = 1 days;
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant PROPOSAL_THRESHOLD = 100000 * 10**18; // 100,000 JGT
    
    event ProposalCreated(
        uint256 indexed proposalId,
        address proposer,
        string description,
        uint256 startTime,
        uint256 endTime
    );
    
    event Voted(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 votes
    );
    
    event ProposalExecuted(uint256 indexed proposalId);
    
    constructor(address _token) {
        token = JGTToken(_token);
    }
    
    function propose(string memory description) external returns (uint256) {
        require(
            token.balanceOf(msg.sender) >= PROPOSAL_THRESHOLD,
            "Must have enough tokens to propose"
        );
        
        uint256 proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];
        
        proposal.proposer = msg.sender;
        proposal.description = description;
        proposal.startTime = block.timestamp + VOTING_DELAY;
        proposal.endTime = proposal.startTime + VOTING_PERIOD;
        
        emit ProposalCreated(
            proposalId,
            msg.sender,
            description,
            proposal.startTime,
            proposal.endTime
        );
        
        return proposalId;
    }
    
    function castVote(uint256 proposalId, bool support) external {
        require(canVote(proposalId), "Voting is not active");
        
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.hasVoted[msg.sender], "Already voted");
        
        uint256 votes = token.balanceOf(msg.sender);
        require(votes > 0, "Must have voting power");
        
        proposal.hasVoted[msg.sender] = true;
        
        if (support) {
            proposal.forVotes += votes;
        } else {
            proposal.againstVotes += votes;
        }
        
        emit Voted(proposalId, msg.sender, support, votes);
    }
    
    function executeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp > proposal.endTime, "Voting period not ended");
        require(!proposal.executed, "Proposal already executed");
        require(isSucceeded(proposalId), "Proposal not succeeded");
        
        proposal.executed = true;
        
        emit ProposalExecuted(proposalId);
    }
    
    function getProposal(uint256 proposalId) external view returns (ProposalInfo memory) {
        Proposal storage proposal = proposals[proposalId];
        return ProposalInfo({
            proposer: proposal.proposer,
            description: proposal.description,
            forVotes: proposal.forVotes,
            againstVotes: proposal.againstVotes,
            startTime: proposal.startTime,
            endTime: proposal.endTime,
            executed: proposal.executed
        });
    }
    
    function isSucceeded(uint256 proposalId) public view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        return proposal.forVotes > proposal.againstVotes && 
               proposal.forVotes > (token.totalSupply() * 10) / 100; // 10% quorum
    }
    
    function canVote(uint256 proposalId) public view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        return block.timestamp >= proposal.startTime && 
               block.timestamp <= proposal.endTime &&
               !proposal.executed;
    }

    function getVotingPower(address account) external view returns (uint256) {
        return token.balanceOf(account);
    }

    function hasVoted(uint256 proposalId, address account) external view returns (bool) {
        return proposals[proposalId].hasVoted[account];
    }
}

interface IGovernanceTarget {
    function executeProposal(bytes memory data) external returns (bool);
}

// Example Target Contract for Governance
contract GovernanceTarget is IGovernanceTarget, Ownable {
    uint256 public someValue;
    address public governanceContract;
    
    constructor(address _governanceContract) Ownable(msg.sender) {
        governanceContract = _governanceContract;
    }
    
    function executeProposal(bytes memory data) external returns (bool) {
        require(msg.sender == governanceContract, "Only governance");
        (uint256 newValue) = abi.decode(data, (uint256));
        someValue = newValue;
        return true;
    }
}
