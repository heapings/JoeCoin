// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract JGTToken is ERC20, Ownable {
    constructor() ERC20("Joe's Governance Token", "JGT") Ownable(msg.sender) {
        _mint(msg.sender, 1000000 * 10**decimals()); // Initial supply: 1 million JGT
    }
}

contract JGTStaking is ReentrancyGuard, Ownable {
    JGTToken public immutable jgtToken;
    JoeCoin public immutable joeCoin;
    
    struct StakingInfo {
        uint256 amount;
        uint256 startTime;
        uint256 rewardDebt;
    }
    
    struct PoolInfo {
        uint256 lastRewardTime;
        uint256 accRewardPerShare;
        uint256 totalStaked;
    }
    
    mapping(address => StakingInfo) public stakingInfo;
    PoolInfo public poolInfo;
    
    uint256 public rewardRate = 100 * 10**18; // 100 JGT per day
    uint256 public constant REWARD_PRECISION = 1e12;
    
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    
    constructor(address _jgtToken, address _joeCoin) Ownable(msg.sender) {
        jgtToken = JGTToken(_jgtToken);
        joeCoin = JoeCoin(_joeCoin);
        poolInfo.lastRewardTime = block.timestamp;
    }
    
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");
        updatePool();
        
        if (stakingInfo[msg.sender].amount > 0) {
            uint256 pending = calculateReward(msg.sender);
            if (pending > 0) {
                jgtToken.transfer(msg.sender, pending);
            }
        }
        
        joeCoin.transferFrom(msg.sender, address(this), amount);
        stakingInfo[msg.sender].amount += amount;
        stakingInfo[msg.sender].startTime = block.timestamp;
        stakingInfo[msg.sender].rewardDebt = stakingInfo[msg.sender].amount * 
            poolInfo.accRewardPerShare / REWARD_PRECISION;
        poolInfo.totalStaked += amount;
        
        emit Staked(msg.sender, amount);
    }
    
    // [Rest of the staking contract implementation remains the same, just with JoeCoin references]
}

contract LiquidityMining is ReentrancyGuard, Ownable {
    JGTToken public immutable jgtToken;
    JoeCoin public immutable joeCoin;
    
    // [Rest of the liquidity mining contract implementation remains the same, just with JoeCoin references]
}
