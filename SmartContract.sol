// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MagnumOpusToken is ERC20, Ownable {
    using SafeMath for uint256;

    uint256 private constant INITIAL_SUPPLY = 1_000_000_000 * 10**18;
    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 * 10**18;

    uint256 private _totalStaked;
    uint256 private _rewardRate;
    uint256 private _lastUpdateTime;

    mapping(address => uint256) private _stakes;
    mapping(address => uint256) private _rewards;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    constructor() ERC20("Magnum Opus Token", "MOPUS") {
        _mint(msg.sender, TOTAL_SUPPLY);
        _rewardRate = 10000000000000000; // 0.01 MOPUS per second
    }

    function stake(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _updateReward(msg.sender);
        _stakes[msg.sender] = _stakes[msg.sender].add(amount);
        _totalStaked = _totalStaked.add(amount);
        _transfer(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(_stakes[msg.sender] >= amount, "Insufficient staked balance");

        _updateReward(msg.sender);
        _stakes[msg.sender] = _stakes[msg.sender].sub(amount);
        _totalStaked = _totalStaked.sub(amount);
        _transfer(address(this), msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    function claimRewards() external {
        _updateReward(msg.sender);
        uint256 reward = _rewards[msg.sender];
        if (reward > 0) {
            _rewards[msg.sender] = 0;
            _transfer(address(this), msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function getStakedBalance(address user) external view returns (uint256) {
        return _stakes[user];
    }

    function getPendingRewards(address user) external view returns (uint256) {
        _updateReward(user);
        return _rewards[user];
    }

    function setRewardRate(uint256 newRate) external onlyOwner {
        _rewardRate = newRate;
    }

    function _updateReward(address user) private {
        uint256 currentTime = block.timestamp;
        uint256 timeElapsed = currentTime.sub(_lastUpdateTime);
        if (timeElapsed > 0 && _totalStaked > 0) {
            uint256 reward = timeElapsed.mul(_rewardRate).mul(_stakes[user]).div(_totalStaked);
            _rewards[user] = _rewards[user].add(reward);
            _lastUpdateTime = currentTime;
        }
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        super._transfer(sender, recipient, amount);
    }
}