// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MagnumOpusToken is ERC20, Ownable {
    using SafeMath for uint256;

    // Token Parameters
    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 private _totalSupply;

    // Staking Parameters
    uint256 private _stakingRewardRate;
    uint256 private _stakingRewardDuration;
    uint256 private _lastRewardUpdateTime;
    mapping(address => uint256) private _stakingBalances;
    mapping(address => uint256) private _rewards;

    // Event Definitions
    event Staked(address indexed staker, uint256 amount);
    event Withdrawn(address indexed staker, uint256 amount);
    event RewardPaid(address indexed staker, uint256 amount);

    // Constructor
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply,
        uint256 stakingRewardRate,
        uint256 stakingRewardDuration
    ) ERC20(name, symbol) {
        _name = name;
        _symbol = symbol;
        _decimals = decimals;
        _stakingRewardRate = stakingRewardRate;
        _stakingRewardDuration = stakingRewardDuration;
        _lastRewardUpdateTime = block.timestamp;

        _mint(msg.sender, initialSupply);
        _totalSupply = initialSupply;
    }

    // Token Functions
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    // Staking Functions
    function stake(uint256 amount) public {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _updateRewards(msg.sender);
        _stakingBalances[msg.sender] = _stakingBalances[msg.sender].add(amount);
        _transfer(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public {
        require(amount > 0, "Amount must be greater than 0");
        require(_stakingBalances[msg.sender] >= amount, "Insufficient staked balance");

        _updateRewards(msg.sender);
        _stakingBalances[msg.sender] = _stakingBalances[msg.sender].sub(amount);
        _transfer(address(this), msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function claimRewards() public {
        _updateRewards(msg.sender);
        uint256 reward = _rewards[msg.sender];
        _rewards[msg.sender] = 0;

        if (reward > 0) {
            _transfer(address(this), msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    // Internal Functions
    function _updateRewards(address account) internal {
        uint256 timeSinceLastUpdate = block.timestamp.sub(_lastRewardUpdateTime);
        if (timeSinceLastUpdate > 0) {
            uint256 reward = _stakingBalances[account].mul(_stakingRewardRate).mul(timeSinceLastUpdate).div(_stakingRewardDuration);
            _rewards[account] = _rewards[account].add(reward);
            _lastRewardUpdateTime = block.timestamp;
        }
    }

    // Admin Functions
    function setStakingRewardRate(uint256 newRate) public onlyOwner {
        _stakingRewardRate = newRate;
    }

    function setStakingRewardDuration(uint256 newDuration) public onlyOwner {
        _stakingRewardDuration = newDuration;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        _mint(to, amount);
        _totalSupply = _totalSupply.add(amount);
    }

    function burn(uint256 amount) public {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _burn(msg.sender, amount);
        _totalSupply = _totalSupply.sub(amount);
    }
}