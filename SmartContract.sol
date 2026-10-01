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

    // Staking parameters
    uint256 private _stakingRewardRate;
    uint256 private _lastUpdateTime;
    mapping(address => uint256) private _stakedBalances;
    mapping(address => uint256) private _rewards;

    // Event declarations
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    // Constructor
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply,
        uint256 stakingRewardRate
    ) ERC20(name, symbol) {
        _name = name;
        _symbol = symbol;
        _decimals = decimals;
        _stakingRewardRate = stakingRewardRate;
        _mint(msg.sender, initialSupply);
        _totalSupply = initialSupply;
        _lastUpdateTime = block.timestamp;
    }

    // Modifier to check if staking amount is valid
    modifier validStakeAmount(uint256 amount) {
        require(amount > 0, "Stake amount must be greater than 0");
        _;
    }

    // Stake tokens
    function stake(uint256 amount) external validStakeAmount(amount) {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _updateRewards(msg.sender);
        _stakedBalances[msg.sender] = _stakedBalances[msg.sender].add(amount);
        _transfer(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    // Withdraw staked tokens
    function withdraw(uint256 amount) external validStakeAmount(amount) {
        require(_stakedBalances[msg.sender] >= amount, "Insufficient staked balance");
        _updateRewards(msg.sender);
        _stakedBalances[msg.sender] = _stakedBalances[msg.sender].sub(amount);
        _transfer(address(this), msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    // Claim rewards
    function claimRewards() external {
        _updateRewards(msg.sender);
        uint256 reward = _rewards[msg.sender];
        if (reward > 0) {
            _rewards[msg.sender] = 0;
            _mint(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    // Update rewards for a user
    function _updateRewards(address user) private {
        uint256 currentTime = block.timestamp;
        uint256 timeElapsed = currentTime.sub(_lastUpdateTime);
        if (timeElapsed > 0) {
            uint256 reward = _stakedBalances[user].mul(_stakingRewardRate).mul(timeElapsed).div(1 days);
            _rewards[user] = _rewards[user].add(reward);
            _lastUpdateTime = currentTime;
        }
    }

    // Get staked balance of a user
    function getStakedBalance(address user) external view returns (uint256) {
        return _stakedBalances[user];
    }

    // Get rewards of a user
    function getRewards(address user) external view returns (uint256) {
        _updateRewards(user);
        return _rewards[user];
    }

    // Get total staked amount
    function getTotalStaked() external view returns (uint256) {
        return balanceOf(address(this));
    }

    // Get staking reward rate
    function getStakingRewardRate() external view returns (uint256) {
        return _stakingRewardRate;
    }

    // Set staking reward rate (only owner)
    function setStakingRewardRate(uint256 newRate) external onlyOwner {
        _stakingRewardRate = newRate;
    }
}