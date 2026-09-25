// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MagnumOpusToken is ERC20, Ownable {
    using SafeMath for uint256;

    // Token parameters
    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 private _totalSupply;

    // Token distribution
    address public teamWallet;
    address public marketingWallet;
    address public ecosystemFund;

    // Staking parameters
    uint256 public stakingRewardRate;
    uint256 public stakingRewardDuration;
    uint256 public lastUpdateTime;
    mapping(address => uint256) public stakingBalances;
    mapping(address => uint256) public stakingRewards;

    // Event declarations
    event TokenPurchase(address indexed buyer, uint256 amount);
    event StakingUpdate(address indexed user, uint256 amount, bool isStake);

    // Modifiers
    modifier onlyWhileActive() {
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Token sale is not active");
        _;
    }

    // Constructor
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply,
        address _teamWallet,
        address _marketingWallet,
        address _ecosystemFund
    ) ERC20(name, symbol) {
        _name = name;
        _symbol = symbol;
        _decimals = decimals;
        _totalSupply = initialSupply * (10 ** uint256(decimals));
        teamWallet = _teamWallet;
        marketingWallet = _marketingWallet;
        ecosystemFund = _ecosystemFund;

        // Distribute initial supply
        _mint(teamWallet, initialSupply.mul(30).mul(10 ** uint256(decimals)).div(100));
        _mint(marketingWallet, initialSupply.mul(20).mul(10 ** uint256(decimals)).div(100));
        _mint(ecosystemFund, initialSupply.mul(50).mul(10 ** uint256(decimals)).div(100));

        // Initialize staking parameters
        stakingRewardRate = 100; // 100 tokens per second
        stakingRewardDuration = 30 days;
        lastUpdateTime = block.timestamp;
    }

    // Token sale functions
    function buyTokens() external payable onlyWhileActive {
        uint256 tokenAmount = msg.value.mul(10 ** uint256(_decimals));
        require(tokenAmount > 0, "Invalid token amount");

        _mint(msg.sender, tokenAmount);
        emit TokenPurchase(msg.sender, tokenAmount);
    }

    // Staking functions
    function stake(uint256 amount) external {
        require(amount > 0, "Stake amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _transfer(msg.sender, address(this), amount);
        stakingBalances[msg.sender] = stakingBalances[msg.sender].add(amount);
        emit StakingUpdate(msg.sender, amount, true);
    }

    function unstake(uint256 amount) external {
        require(amount > 0, "Unstake amount must be greater than 0");
        require(stakingBalances[msg.sender] >= amount, "Insufficient staked balance");

        _updateRewards(msg.sender);
        stakingBalances[msg.sender] = stakingBalances[msg.sender].sub(amount);
        _transfer(address(this), msg.sender, amount);
        emit StakingUpdate(msg.sender, amount, false);
    }

    function claimRewards() external {
        _updateRewards(msg.sender);
        uint256 reward = stakingRewards[msg.sender];
        if (reward > 0) {
            stakingRewards[msg.sender] = 0;
            _transfer(address(this), msg.sender, reward);
        }
    }

    // Internal functions
    function _updateRewards(address user) internal {
        uint256 timePassed = block.timestamp.sub(lastUpdateTime);
        if (timePassed > 0) {
            uint256 reward = stakingBalances[user].mul(stakingRewardRate).mul(timePassed).div(1e18);
            stakingRewards[user] = stakingRewards[user].add(reward);
            lastUpdateTime = block.timestamp;
        }
    }

    // View functions
    function getStakingRewards(address user) external view returns (uint256) {
        _updateRewards(user);
        return stakingRewards[user];
    }

    function getTotalStaked() external view returns (uint256) {
        return balanceOf(address(this));
    }
}