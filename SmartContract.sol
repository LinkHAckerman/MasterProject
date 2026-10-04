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

    // Modifier to check if contract is paused
    modifier whenNotPaused() {
        require(!paused(), "Contract is paused");
        _;
    }

    // Function to stake tokens
    function stake(uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _updateRewards(msg.sender);
        _stakedBalances[msg.sender] = _stakedBalances[msg.sender].add(amount);
        _transfer(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    // Function to withdraw staked tokens
    function withdraw(uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(_stakedBalances[msg.sender] >= amount, "Insufficient staked balance");

        _updateRewards(msg.sender);
        _stakedBalances[msg.sender] = _stakedBalances[msg.sender].sub(amount);
        _transfer(address(this), msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    // Function to claim rewards
    function claimRewards() external whenNotPaused {
        _updateRewards(msg.sender);
        uint256 reward = _rewards[msg.sender];
        _rewards[msg.sender] = 0;

        if (reward > 0) {
            _mint(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    // Function to update rewards for a user
    function _updateRewards(address user) private {
        uint256 currentTime = block.timestamp;
        uint256 timeElapsed = currentTime.sub(_lastUpdateTime);

        if (timeElapsed > 0) {
            uint256 reward = _stakedBalances[user].mul(_stakingRewardRate).mul(timeElapsed);
            _rewards[user] = _rewards[user].add(reward);
            _lastUpdateTime = currentTime;
        }
    }

    // Function to get staked balance of a user
    function getStakedBalance(address user) external view returns (uint256) {
        return _stakedBalances[user];
    }

    // Function to get pending rewards of a user
    function getPendingRewards(address user) external view returns (uint256) {
        uint256 currentTime = block.timestamp;
        uint256 timeElapsed = currentTime.sub(_lastUpdateTime);

        if (timeElapsed > 0) {
            return _stakedBalances[user].mul(_stakingRewardRate).mul(timeElapsed).add(_rewards[user]);
        } else {
            return _rewards[user];
        }
    }

    // Function to get total supply
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    // Function to mint tokens
    function _mint(address account, uint256 amount) internal override {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply = _totalSupply.add(amount);
        super._mint(account, amount);
    }

    // Function to burn tokens
    function _burn(address account, uint256 amount) internal override {
        require(account != address(0), "ERC20: burn from the zero address");
        require(balanceOf(account) >= amount, "ERC20: burn amount exceeds balance");

        _totalSupply = _totalSupply.sub(amount);
        super._burn(account, amount);
    }

    // Function to transfer tokens
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        super._transfer(sender, recipient, amount);
    }

    // Function to transfer tokens from one address to another
    function _transferFrom(
        address sender,
        address recipient,
        address spender,
        uint256 amount
    ) internal override {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        super._transferFrom(sender, recipient, spender, amount);
    }

    // Function to approve tokens for spending
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal override {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        super._approve(owner, spender, amount);
    }

    // Function to increase allowance
    function _increaseAllowance(
        address owner,
        address spender,
        uint256 addedValue
    ) internal override {
        require(owner != address(0), "ERC20: increase allowance from the zero address");
        require(spender != address(0), "ERC20: increase allowance to the zero address");

        super._increaseAllowance(owner, spender, addedValue);
    }

    // Function to decrease allowance
    function _decreaseAllowance(
        address owner,
        address spender,
        uint256 subtractedValue
    ) internal override {
        require(owner != address(0), "ERC20: decrease allowance from the zero address");
        require(spender != address(0), "ERC20: decrease allowance to the zero address");

        super._decreaseAllowance(owner, spender, subtractedValue);
    }
}