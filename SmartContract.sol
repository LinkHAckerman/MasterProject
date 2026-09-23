// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MagnumOpusToken is ERC20, Ownable {
    using SafeMath for uint256;

    // Token parameters
    string public constant name = "Magnum Opus Token";
    string public constant symbol = "MOPUS";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_000_000_000 * (10 ** decimals);

    // Staking parameters
    uint256 public stakingRewardRate = 0.0045 ether;
    uint256 public stakingRewardInterval = 1 days;
    uint256 public minimumStakeAmount = 100 * (10 ** decimals);

    // Contract state
    mapping(address => uint256) public stakedBalances;
    mapping(address => uint256) public rewards;
    uint256 public lastRewardUpdate;

    // Events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);

    // Modifiers
    modifier onlyStaker(address _user) {
        require(stakedBalances[_user] > 0, "Not a staker");
        _;
    }

    // Constructor
    constructor() ERC20(name, symbol) {
        _mint(msg.sender, totalSupply);
        lastRewardUpdate = block.timestamp;
    }

    // Staking functions
    function stake(uint256 _amount) external {
        require(_amount >= minimumStakeAmount, "Amount too low");
        require(balanceOf(msg.sender) >= _amount, "Insufficient balance");

        _transfer(msg.sender, address(this), _amount);
        stakedBalances[msg.sender] = stakedBalances[msg.sender].add(_amount);

        emit Staked(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external onlyStaker(msg.sender) {
        require(_amount <= stakedBalances[msg.sender], "Insufficient staked balance");

        _transfer(address(this), msg.sender, _amount);
        stakedBalances[msg.sender] = stakedBalances[msg.sender].sub(_amount);

        emit Withdrawn(msg.sender, _amount);
    }

    function claimRewards() external onlyStaker(msg.sender) {
        uint256 reward = calculateReward(msg.sender);
        require(reward > 0, "No rewards to claim");

        rewards[msg.sender] = 0;
        _transfer(address(this), msg.sender, reward);

        emit RewardClaimed(msg.sender, reward);
    }

    // View functions
    function calculateReward(address _user) public view returns (uint256) {
        uint256 timeElapsed = block.timestamp.sub(lastRewardUpdate);
        uint256 reward = stakedBalances[_user].mul(stakingRewardRate).mul(timeElapsed).div(stakingRewardInterval);
        return reward.add(rewards[_user]);
    }

    function getStakedBalance(address _user) external view returns (uint256) {
        return stakedBalances[_user];
    }

    function getRewards(address _user) external view returns (uint256) {
        return calculateReward(_user);
    }

    // Admin functions
    function setStakingRewardRate(uint256 _newRate) external onlyOwner {
        stakingRewardRate = _newRate;
    }

    function setMinimumStakeAmount(uint256 _newAmount) external onlyOwner {
        minimumStakeAmount = _newAmount;
    }

    // Fallback function
    fallback() external payable {
        revert("Direct ETH transfers not allowed");
    }

    // Receive function
    receive() external payable {
        revert("Direct ETH transfers not allowed");
    }
}