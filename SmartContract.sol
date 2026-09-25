// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MagnumOpusToken is ERC20, Ownable {
    using SafeMath for uint256;

    uint256 private constant INITIAL_SUPPLY = 1_000_000_000 * 10**18;
    uint256 private constant MAX_SUPPLY = 10_000_000_000 * 10**18;

    address public stakingContract;
    uint256 public stakingRewardRate = 100;
    uint256 public lastUpdateTime;

    event StakingContractSet(address indexed newStakingContract);
    event StakingRewardRateUpdated(uint256 newRate);

    constructor() ERC20("MagnumOpus Token", "MOT") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function setStakingContract(address _stakingContract) public onlyOwner {
        stakingContract = _stakingContract;
        emit StakingContractSet(_stakingContract);
    }

    function updateStakingRewardRate(uint256 _newRate) public onlyOwner {
        stakingRewardRate = _newRate;
        emit StakingRewardRateUpdated(_newRate);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        require(totalSupply().add(amount) <= MAX_SUPPLY, "Exceeds maximum supply");
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        virtual
        override
    {
        super._beforeTokenTransfer(from, to, amount);
        if (from != address(0) && to != address(0)) {
            require(from != stakingContract, "Cannot transfer from staking contract");
            require(to != stakingContract, "Cannot transfer to staking contract");
        }
    }

    function calculateStakingRewards(uint256 amount, uint256 duration) public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        uint256 reward = amount.mul(stakingRewardRate).mul(timeElapsed).div(1 days).div(100);
        return reward.mul(duration).div(1 days);
    }

    function updateLastUpdateTime() public {
        lastUpdateTime = block.timestamp;
    }
}

contract MagnumOpusStaking is Ownable {
    using SafeMath for uint256;

    MagnumOpusToken public token;
    uint256 public totalStaked;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;

    mapping(address => uint256) public stakedBalances;
    mapping(address => uint256) public rewards;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 newRate);

    constructor(address _tokenAddress) {
        token = MagnumOpusToken(_tokenAddress);
        lastUpdateTime = block.timestamp;
    }

    modifier onlyTokenContract() {
        require(msg.sender == address(token), "Only token contract can call this function");
        _;
    }

    function stake(uint256 amount) public {
        require(amount > 0, "Amount must be greater than 0");
        require(token.balanceOf(msg.sender) >= amount, "Insufficient balance");

        token.transferFrom(msg.sender, address(this), amount);
        stakedBalances[msg.sender] = stakedBalances[msg.sender].add(amount);
        totalStaked = totalStaked.add(amount);

        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public {
        require(amount > 0, "Amount must be greater than 0");
        require(stakedBalances[msg.sender] >= amount, "Insufficient staked balance");

        _updateRewards(msg.sender);

        stakedBalances[msg.sender] = stakedBalances[msg.sender].sub(amount);
        totalStaked = totalStaked.sub(amount);

        token.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function claimRewards() public {
        _updateRewards(msg.sender);

        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            token.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function updateRewardRate(uint256 _newRate) public onlyOwner {
        rewardRate = _newRate;
        emit RewardRateUpdated(_newRate);
    }

    function _updateRewards(address user) internal {
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        if (timeElapsed > 0 && totalStaked > 0) {
            uint256 reward = totalStaked.mul(rewardRate).mul(timeElapsed).div(1 days).div(100);
            rewards[user] = rewards[user].add(reward);
            lastUpdateTime = block.timestamp;
        }
    }

    function getStakedBalance(address user) public view returns (uint256) {
        return stakedBalances[user];
    }

    function getRewards(address user) public view returns (uint256) {
        _updateRewards(user);
        return rewards[user];
    }
}