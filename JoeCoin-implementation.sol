// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";


// Price Oracle Interface
interface IPriceOracle {
    function getPrice(address asset) external view returns (uint256);
}

// JoeCoin - The stablecoin token
contract JoeCoin is ERC20, Ownable {
    constructor() ERC20("JoeCoin", "JOE") Ownable(msg.sender) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}

// Vault contract to manage collateral and debt
contract JoeVault is ReentrancyGuard, Ownable {
    struct Vault {
        uint256 collateralAmount;
        uint256 debtAmount;
        uint256 lastInterestUpdate;
    }

    JoeCoin public immutable joeCoin;
    IPriceOracle public immutable priceOracle;
    
    mapping(address => Vault) public vaults;
    mapping(address => bool) public supportedCollateral;
    
    uint256 public minimumCollateralRatio = 150; // 150%
    uint256 public liquidationThreshold = 130; // 130%
    uint256 public stabilityFee = 5; // 0.5% annual
    uint256 public liquidationPenalty = 130; // 13%
    
    event VaultCreated(address indexed owner, uint256 collateralAmount, uint256 debtAmount);
    event VaultModified(address indexed owner, uint256 collateralAmount, uint256 debtAmount);
    event VaultLiquidated(address indexed owner, address liquidator, uint256 debtCovered);

    constructor(address _joeCoin, address _priceOracle) Ownable(msg.sender) {
        joeCoin = JoeCoin(_joeCoin);
        priceOracle = IPriceOracle(_priceOracle);
    }

    function setCollateralSupport(address collateral, bool supported) external onlyOwner {
        supportedCollateral[collateral] = supported;
    }

    function createVault(
        address collateralToken,
        uint256 collateralAmount,
        uint256 debtAmount
    ) external nonReentrant {
        require(supportedCollateral[collateralToken], "Unsupported collateral");
        
        IERC20(collateralToken).transferFrom(msg.sender, address(this), collateralAmount);
        
        uint256 collateralValue = getCollateralValue(collateralToken, collateralAmount);
        require(
            collateralValue * 100 >= debtAmount * minimumCollateralRatio,
            "Insufficient collateral ratio"
        );
        
        Vault storage vault = vaults[msg.sender];
        vault.collateralAmount += collateralAmount;
        vault.debtAmount += debtAmount;
        vault.lastInterestUpdate = block.timestamp;
        
        joeCoin.mint(msg.sender, debtAmount);
        
        emit VaultCreated(msg.sender, collateralAmount, debtAmount);
    }

    function repayDebt(
        address collateralToken,
        uint256 repayAmount,
        uint256 collateralToWithdraw
    ) external nonReentrant {
        Vault storage vault = vaults[msg.sender];
        require(vault.debtAmount >= repayAmount, "Repay amount too high");
        
        uint256 fee = calculateStabilityFee(vault);
        uint256 totalRepayment = repayAmount + fee;
        
        joeCoin.transferFrom(msg.sender, address(this), totalRepayment);
        joeCoin.burn(address(this), totalRepayment);
        
        vault.debtAmount -= repayAmount;
        
        if (collateralToWithdraw > 0) {
            require(vault.collateralAmount >= collateralToWithdraw, "Insufficient collateral");
            
            uint256 remainingCollateral = vault.collateralAmount - collateralToWithdraw;
            uint256 remainingCollateralValue = getCollateralValue(
                collateralToken,
                remainingCollateral
            );
            
            require(
                vault.debtAmount == 0 || 
                remainingCollateralValue * 100 >= vault.debtAmount * minimumCollateralRatio,
                "Would breach collateral ratio"
            );
            
            vault.collateralAmount = remainingCollateral;
            IERC20(collateralToken).transfer(msg.sender, collateralToWithdraw);
        }
        
        vault.lastInterestUpdate = block.timestamp;
        emit VaultModified(msg.sender, vault.collateralAmount, vault.debtAmount);
    }

    function liquidateVault(
        address vaultOwner,
        address collateralToken,
        uint256 debtToCover
    ) external nonReentrant {
        Vault storage vault = vaults[vaultOwner];
        require(isLiquidatable(vaultOwner, collateralToken), "Vault not liquidatable");
        require(debtToCover <= vault.debtAmount, "Debt amount too high");
        
        uint256 collateralPrice = priceOracle.getPrice(collateralToken);
        uint256 collateralToSeize = (debtToCover * liquidationPenalty * 1e18) / 
                                  (collateralPrice * 100);
        
        require(collateralToSeize <= vault.collateralAmount, "Insufficient collateral");
        
        joeCoin.transferFrom(msg.sender, address(this), debtToCover);
        joeCoin.burn(address(this), debtToCover);
        
        vault.debtAmount -= debtToCover;
        vault.collateralAmount -= collateralToSeize;
        
        IERC20(collateralToken).transfer(msg.sender, collateralToSeize);
        
        emit VaultLiquidated(vaultOwner, msg.sender, debtToCover);
    }

    function getCollateralValue(address collateralToken, uint256 amount) public view returns (uint256) {
        uint256 price = priceOracle.getPrice(collateralToken);
        return (price * amount) / 1e18;
    }
    
    function calculateStabilityFee(Vault memory vault) public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - vault.lastInterestUpdate;
        return (vault.debtAmount * stabilityFee * timeElapsed) / (365 days * 1000);
    }
    
    function isLiquidatable(address vaultOwner, address collateralToken) public view returns (bool) {
        Vault memory vault = vaults[vaultOwner];
        if (vault.debtAmount == 0) return false;
        
        uint256 collateralValue = getCollateralValue(collateralToken, vault.collateralAmount);
        return collateralValue * 100 < vault.debtAmount * liquidationThreshold;
    }

    function setMinimumCollateralRatio(uint256 _ratio) external onlyOwner {
        require(_ratio >= 100, "Invalid ratio");
        minimumCollateralRatio = _ratio;
    }
    
    function setLiquidationThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold >= 100 && _threshold < minimumCollateralRatio, "Invalid threshold");
        liquidationThreshold = _threshold;
    }
    
    function setStabilityFee(uint256 _fee) external onlyOwner {
        stabilityFee = _fee;
    }
    
    function setLiquidationPenalty(uint256 _penalty) external onlyOwner {
        require(_penalty >= 100, "Invalid penalty");
        liquidationPenalty = _penalty;
    }
}

// Basic price oracle implementation
contract SimplePriceOracle is IPriceOracle, Ownable {
    mapping(address => uint256) public prices;
    
    constructor() Ownable(msg.sender) {}
    
    function setPrice(address asset, uint256 price) external onlyOwner {
        prices[asset] = price;
    }
    
    function getPrice(address asset) external view override returns (uint256) {
        require(prices[asset] > 0, "Price not set");
        return prices[asset];
    }
}
