// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Governance is ReentrancyGuard, Ownable {
    JGTToken public immutable token;

    struct Proposal {
        address proposer;
        string description;
        uint256 alpha;
        uint256 beta;  
        uint256 gamma;
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
        uint256 alpha;
        uint256 beta;  
        uint256 gamma;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        bool executed;
    }

    uint256 public alpha; 
    uint256 public beta;  
    uint256 public gamma; 

    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;

    uint256 public constant VOTING_DELAY = 1 days;
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant PROPOSAL_THRESHOLD = 100000 * 10**18; // 100,000 JGT
    uint256 public proposalCreationFee = 500 * 10**18; // Fee to deter spam 500 JGT

    bool public emergencyPaused = false;

    event ProposalCreated(
        uint256 indexed proposalId,
        address proposer,
        string description,
        uint256 alpha,
        uint256 beta,
        uint256 gamma,
        uint256 startTime,
        uint256 endTime
    );

    event Voted(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 votes
    );

    event ProposalExecuted(
        uint256 indexed proposalId,
        uint256 alpha,
        uint256 beta,
        uint256 gamma
    );

    event ParametersUpdated(uint256 alpha, uint256 beta, uint256 gamma);

    event EmergencyPaused(bool paused);

    constructor(address _token) {
        token = JGTToken(_token);

        alpha = 1e18; // Default alpha = 1
        beta = 1e18;  // Default beta = 1
        gamma = 5e16; // Default gamma = 0.05

        emit ParametersUpdated(alpha, beta, gamma);
    }

    function propose(
        string memory description,
        uint256 _alpha,
        uint256 _beta,
        uint256 _gamma
    ) external payable returns (uint256) {
        require(
            token.balanceOf(msg.sender, block.number - 1) >= PROPOSAL_THRESHOLD,
            "Must have enough tokens to propose"
        );
        require(msg.value >= proposalCreationFee, "Insufficient fee");
        require(_alpha >= 0.01e18 && _alpha <= 0.1e18, "Alpha must be between 0.01 and 0.1");
        require(_beta >= 0.01e18 && _beta <= 0.1e18, "Beta must be between 0.01 and 0.1");
        require(_gamma >= 0.05e18 && _gamma <= 0.5e18, "Gamma must be between 0.05 and 0.5");
        require(
            _alpha != alpha || _beta != beta || _gamma != gamma,
            "Proposal must change at least one parameter"
        );

        uint256 proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];

        proposal.proposer = msg.sender;
        proposal.description = description;
        proposal.alpha = _alpha;
        proposal.beta = _beta;
        proposal.gamma = _gamma;
        proposal.startTime = block.timestamp + VOTING_DELAY;
        proposal.endTime = proposal.startTime + VOTING_PERIOD;

        emit ProposalCreated(
            proposalId,
            msg.sender,
            description,
            _alpha,
            _beta,
            _gamma,
            proposal.startTime,
            proposal.endTime
        );

        return proposalId;
    }

    function castVote(uint256 proposalId, bool support) external nonReentrant {
        require(canVote(proposalId), "Voting is not active");
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.hasVoted[msg.sender], "Already voted");

        uint256 votes = token.balanceOf(msg.sender, proposal.startTime);
        require(votes > 0, "Must have voting power");

        proposal.hasVoted[msg.sender] = true;

        if (support) {
            proposal.forVotes += votes;
        } else {
            proposal.againstVotes += votes;
        }

        emit Voted(proposalId, msg.sender, support, votes);
    }

    function executeProposal(uint256 proposalId) external nonReentrant {
        require(!emergencyPaused, "Emergency pause activated");

        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp > proposal.endTime, "Voting period not ended");
        require(block.timestamp <= proposal.endTime + 7 days, "Proposal expired");
        require(!proposal.executed, "Proposal already executed");
        require(isSucceeded(proposalId), "Proposal not succeeded");

        alpha = proposal.alpha;
        beta = proposal.beta;
        gamma = proposal.gamma;
        proposal.executed = true;

        emit ProposalExecuted(proposalId, alpha, beta, gamma);
        emit ParametersUpdated(alpha, beta, gamma);
    }

    function getProposal(uint256 proposalId) external view returns (ProposalInfo memory) {
        Proposal storage proposal = proposals[proposalId];
        return ProposalInfo({
            proposer: proposal.proposer,
            description: proposal.description,
            alpha: proposal.alpha,
            beta: proposal.beta,
            gamma: proposal.gamma,
            forVotes: proposal.forVotes,
            againstVotes: proposal.againstVotes,
            startTime: proposal.startTime,
            endTime: proposal.endTime,
            executed: proposal.executed
        });
    }
    
    function toggleEmergencyPause() external onlyOwner {
        emergencyPaused = !emergencyPaused;
        emit EmergencyPaused(emergencyPaused);
    }

    function isSucceeded(uint256 proposalId) public view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        return proposal.forVotes > proposal.againstVotes &&
               proposal.forVotes > (token.totalSupply(block.number - 1) * 10) / 100; // 10% quorum
    }

    function canVote(uint256 proposalId) public view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        return block.timestamp >= proposal.startTime &&
               block.timestamp <= proposal.endTime &&
               !proposal.executed;
    }

    function updateProposalCreationFee(uint256 newFee) external onlyOwner {
        proposalCreationFee = newFee;
    }

    function getVotingPower(address account) external view returns (uint256) {
        return token.balanceOf(account);
    }
}

