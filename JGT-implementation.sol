// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./JoeCoin-implementation.sol";

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
    
    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot withdraw 0");
        require(stakingInfo[msg.sender].amount >= amount, "Insufficient balance");
        
        updatePool();
        uint256 pending = calculateReward(msg.sender);
        
        stakingInfo[msg.sender].amount -= amount;
        stakingInfo[msg.sender].rewardDebt = stakingInfo[msg.sender].amount * 
            poolInfo.accRewardPerShare / REWARD_PRECISION;
        poolInfo.totalStaked -= amount;
        
        if (pending > 0) {
            jgtToken.transfer(msg.sender, pending);
        }
        joeCoin.transfer(msg.sender, amount);
        
        emit Withdrawn(msg.sender, amount);
        emit RewardClaimed(msg.sender, pending);
    }
    
    function claimReward() external nonReentrant {
        updatePool();
        uint256 pending = calculateReward(msg.sender);
        require(pending > 0, "No rewards to claim");
        
        stakingInfo[msg.sender].rewardDebt = stakingInfo[msg.sender].amount * 
            poolInfo.accRewardPerShare / REWARD_PRECISION;
        
        jgtToken.transfer(msg.sender, pending);
        emit RewardClaimed(msg.sender, pending);
    }
    
    function updatePool() public {
        if (block.timestamp <= poolInfo.lastRewardTime) {
            return;
        }
        
        if (poolInfo.totalStaked == 0) {
            poolInfo.lastRewardTime = block.timestamp;
            return;
        }
        
        uint256 timeElapsed = block.timestamp - poolInfo.lastRewardTime;
        uint256 reward = timeElapsed * rewardRate / 1 days;
        
        poolInfo.accRewardPerShare += reward * REWARD_PRECISION / poolInfo.totalStaked;
        poolInfo.lastRewardTime = block.timestamp;
    }
    
    function calculateReward(address user) public view returns (uint256) {
        StakingInfo memory staker = stakingInfo[user];
        uint256 accRewardPerShare = poolInfo.accRewardPerShare;
        
        if (block.timestamp > poolInfo.lastRewardTime && poolInfo.totalStaked > 0) {
            uint256 timeElapsed = block.timestamp - poolInfo.lastRewardTime;
            uint256 reward = timeElapsed * rewardRate / 1 days;
            accRewardPerShare += reward * REWARD_PRECISION / poolInfo.totalStaked;
        }
        
        return (staker.amount * accRewardPerShare / REWARD_PRECISION) - staker.rewardDebt;
    }
    
    // Governance setters
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        require(_rewardRate > 0, "Invalid reward rate");
        rewardRate = _rewardRate;
    }
}

contract LiquidityMining is ReentrancyGuard, Ownable {
    JGTToken public immutable jgtToken;
    JoeCoin public immutable joeCoin;
    
    struct UserInfo {
        uint256 lpAmount;
        uint256 rewardDebt;
    }
    
    struct PoolInfo {
        uint256 lastRewardTime;
        uint256 accRewardPerShare;
        uint256 totalLpTokens;
    }
    
    mapping(address => UserInfo) public userInfo;
    PoolInfo public poolInfo;
    
    uint256 public rewardRate = 200 * 10**18; // 200 JGT per day for LP providers
    uint256 public constant REWARD_PRECISION = 1e12;
    
    event LiquidityAdded(address indexed user, uint256 amount);
    event LiquidityRemoved(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    
    constructor(address _jgtToken, address _joeCoin) Ownable(msg.sender) {
        jgtToken = JGTToken(_jgtToken);
        joeCoin = JoeCoin(_joeCoin);
        poolInfo.lastRewardTime = block.timestamp;
    }
    
    function addLiquidity(uint256 lpAmount) external nonReentrant {
        require(lpAmount > 0, "Cannot add 0 liquidity");
        updatePool();
        
        if (userInfo[msg.sender].lpAmount > 0) {
            uint256 pending = calculateReward(msg.sender);
            if (pending > 0) {
                jgtToken.transfer(msg.sender, pending);
            }
        }
        
        // Transfer LP tokens (placeholder - in real implementation would use actual LP tokens)
        joeCoin.transferFrom(msg.sender, address(this), lpAmount);
        userInfo[msg.sender].lpAmount += lpAmount;
        userInfo[msg.sender].rewardDebt = userInfo[msg.sender].lpAmount * 
            poolInfo.accRewardPerShare / REWARD_PRECISION;
        poolInfo.totalLpTokens += lpAmount;
        
        emit LiquidityAdded(msg.sender, lpAmount);
    }
    
    function removeLiquidity(uint256 lpAmount) external nonReentrant {
        require(lpAmount > 0, "Cannot remove 0 liquidity");
        require(userInfo[msg.sender].lpAmount >= lpAmount, "Insufficient LP tokens");
        
        updatePool();
        uint256 pending = calculateReward(msg.sender);
        
        userInfo[msg.sender].lpAmount -= lpAmount;
        userInfo[msg.sender].rewardDebt = userInfo[msg.sender].lpAmount * 
            poolInfo.accRewardPerShare / REWARD_PRECISION;
        poolInfo.totalLpTokens -= lpAmount;
        
        if (pending > 0) {
            jgtToken.transfer(msg.sender, pending);
        }
        joeCoin.transfer(msg.sender, lpAmount);
        
        emit LiquidityRemoved(msg.sender, lpAmount);
        emit RewardPaid(msg.sender, pending);
    }
    
    function updatePool() public {
        if (block.timestamp <= poolInfo.lastRewardTime) {
            return;
        }
        
        if (poolInfo.totalLpTokens == 0) {
            poolInfo.lastRewardTime = block.timestamp;
            return;
        }
        
        uint256 timeElapsed = block.timestamp - poolInfo.lastRewardTime;
        uint256 reward = timeElapsed * rewardRate / 1 days;
        
        poolInfo.accRewardPerShare += reward * REWARD_PRECISION / poolInfo.totalLpTokens;
        poolInfo.lastRewardTime = block.timestamp;
    }
    
    function calculateReward(address user) public view returns (uint256) {
        UserInfo memory lpUser = userInfo[user];
        uint256 accRewardPerShare = poolInfo.accRewardPerShare;
        
        if (block.timestamp > poolInfo.lastRewardTime && poolInfo.totalLpTokens > 0) {
            uint256 timeElapsed = block.timestamp - poolInfo.lastRewardTime;
            uint256 reward = timeElapsed * rewardRate / 1 days;
            accRewardPerShare += reward * REWARD_PRECISION / poolInfo.totalLpTokens;
        }
        
        return (lpUser.lpAmount * accRewardPerShare / REWARD_PRECISION) - lpUser.rewardDebt;
    }
    
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        require(_rewardRate > 0, "Invalid reward rate");
        rewardRate = _rewardRate;
    }
}