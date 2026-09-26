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
    uint256 public stakingRewardRate = 1 ether;
    uint256 public stakingDuration = 30 days;
    uint256 public lastUpdateTime;
    mapping(address => uint256) public stakedBalances;
    mapping(address => uint256) public rewards;

    // Events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    // Constructor
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply
    ) ERC20(name, symbol) {
        _name = name;
        _symbol = symbol;
        _decimals = decimals;
        _mint(msg.sender, initialSupply);
        _totalSupply = initialSupply;
    }

    // Staking functions
    function stake(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _transfer(msg.sender, address(this), amount);
        stakedBalances[msg.sender] = stakedBalances[msg.sender].add(amount);
        lastUpdateTime = block.timestamp;

        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(stakedBalances[msg.sender] >= amount, "Insufficient staked balance");

        _updateRewards(msg.sender);
        stakedBalances[msg.sender] = stakedBalances[msg.sender].sub(amount);
        _transfer(address(this), msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function claimRewards() external {
        _updateRewards(msg.sender);
        uint256 reward = rewards[msg.sender];
        rewards[msg.sender] = 0;

        if (reward > 0) {
            _transfer(address(this), msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    // Internal functions
    function _updateRewards(address user) internal {
        uint256 timePassed = block.timestamp.sub(lastUpdateTime);
        if (timePassed > 0 && stakedBalances[user] > 0) {
            uint256 reward = stakedBalances[user].mul(stakingRewardRate).mul(timePassed).div(stakingDuration);
            rewards[user] = rewards[user].add(reward);
            lastUpdateTime = block.timestamp;
        }
    }

    // Override transfer function to prevent transfers during staking
    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        require(stakedBalances[msg.sender] == 0, "Cannot transfer while staking");
        return super.transfer(recipient, amount);
    }

    // Admin functions
    function setStakingRewardRate(uint256 newRate) external onlyOwner {
        stakingRewardRate = newRate;
    }

    function setStakingDuration(uint256 newDuration) external onlyOwner {
        stakingDuration = newDuration;
    }
}