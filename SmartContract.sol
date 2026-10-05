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

    // Events
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

    // Staking functions
    function stake(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _updateRewards(msg.sender);
        _stakedBalances[msg.sender] = _stakedBalances[msg.sender].add(amount);
        _transfer(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(_stakedBalances[msg.sender] >= amount, "Insufficient staked balance");

        _updateRewards(msg.sender);
        _stakedBalances[msg.sender] = _stakedBalances[msg.sender].sub(amount);
        _transfer(address(this), msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function claimRewards() external {
        _updateRewards(msg.sender);
        uint256 reward = _rewards[msg.sender];
        _rewards[msg.sender] = 0;

        if (reward > 0) {
            _transfer(address(this), msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    // View functions
    function getStakedBalance(address user) external view returns (uint256) {
        return _stakedBalances[user];
    }

    function getPendingRewards(address user) external view returns (uint256) {
        uint256 stakedBalance = _stakedBalances[user];
        uint256 timeElapsed = block.timestamp.sub(_lastUpdateTime);
        return stakedBalance.mul(_stakingRewardRate).mul(timeElapsed).div(1 days);
    }

    // Internal functions
    function _updateRewards(address user) internal {
        uint256 stakedBalance = _stakedBalances[user];
        if (stakedBalance > 0) {
            uint256 timeElapsed = block.timestamp.sub(_lastUpdateTime);
            uint256 reward = stakedBalance.mul(_stakingRewardRate).mul(timeElapsed).div(1 days);
            _rewards[user] = _rewards[user].add(reward);
        }
        _lastUpdateTime = block.timestamp;
    }

    // Override transfer function to prevent transfers of staked tokens
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        require(_stakedBalances[msg.sender] == 0, "Cannot transfer staked tokens");
        return super.transfer(recipient, amount);
    }

    // Admin functions
    function setStakingRewardRate(uint256 newRate) external onlyOwner {
        _stakingRewardRate = newRate;
    }

    function mintTokens(uint256 amount) external onlyOwner {
        _mint(msg.sender, amount);
        _totalSupply = _totalSupply.add(amount);
    }
}