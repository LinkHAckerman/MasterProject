// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MagnumOpusDeFiEngine
 * @notice The Ultimate Web3, DeFi, Staking, and Decentralized Exchange Core Module.
 * Part of the MAGNUM OPUS Platform.
 */

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract MagnumOpusToken is IERC20 {
    string public name = "Magnum Opus Protocol";
    string public symbol = "MOPUS";
    uint8 public decimals = 18;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "MagnumOpusToken: caller is not the owner");
        _;
    }

    constructor(uint256 initialSupply) {
        owner = msg.sender;
        _mint(msg.sender, initialSupply * (10 ** uint256(decimals)));
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address ownerAddress, address spender) external view override returns (uint256) {
        return _allowances[ownerAddress][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, msg.sender, currentAllowance - amount);
        }
        _transfer(sender, recipient, amount);
        return true;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from zero address");
        require(recipient != address(0), "ERC20: transfer to zero address");

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to zero address");

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from zero address");

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    function _approve(address ownerAddress, address spender, uint256 amount) internal {
        require(ownerAddress != address(0), "ERC20: approve from zero address");
        require(spender != address(0), "ERC20: approve to zero address");

        _allowances[ownerAddress][spender] = amount;
        emit Approval(ownerAddress, spender, amount);
    }
}

/**
 * @title MagnumOpusStakingVault
 * @notice Simple ERC20 staking vault that distributes reward tokens proportionally to stake.
 */
contract MagnumOpusStakingVault {
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    address public owner;
    uint256 public rewardRate; // reward tokens per second
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(uint256 reward);
    event RewardRateUpdated(uint256 newRate);

    modifier onlyOwner() {
        require(msg.sender == owner, "StakingVault: caller is not the owner");
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    constructor(address _stakingToken, address _rewardToken, uint256 _initialRewardRate) {
        require(_stakingToken != address(0) && _rewardToken != address(0), "StakingVault: token address zero");
        owner = msg.sender;
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardRate = _initialRewardRate;
        lastUpdateTime = block.timestamp;
    }

    /**
     * @dev Returns the current reward per token stored value.
     */
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        uint256 timeDelta = block.timestamp - lastUpdateTime;
        return rewardPerTokenStored + (timeDelta * rewardRate * 1e18) / _totalSupply;
    }

    /**
     * @dev Returns the amount of reward tokens earned by `account`.
     */
    function earned(address account) public view returns (uint256) {
        uint256 accrued = (_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18;
        return rewards[account] + accrued;
    }

    /**
     * @notice Stake `amount` of staking tokens.
     */
    function stake(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "StakingVault: cannot stake 0");
        _totalSupply += amount;
        _balances[msg.sender] += amount;
        require(stakingToken.transferFrom(msg.sender, address(this), amount), "StakingVault: transfer failed");
        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Withdraw `amount` of previously staked tokens.
     */
    function withdraw(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, "StakingVault: cannot withdraw 0");
        require(_balances[msg.sender] >= amount, "StakingVault: withdraw exceeds balance");
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;
        require(stakingToken.transfer(msg.sender, amount), "StakingVault: transfer failed");
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Claim all earned reward tokens.
     */
    function getReward() public updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            require(rewardToken.transfer(msg.sender, reward), "StakingVault: reward transfer failed");
            emit RewardPaid(msg.sender, reward);
        }
    }

    /**
     * @notice Withdraw all staked tokens and claim rewards.
     */
    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /**
     * @notice Owner can update the reward emission rate.
     */
    function setRewardRate(uint256 _newRate) external onlyOwner {
        rewardRate = _newRate;
        emit RewardRateUpdated(_newRate);
    }

    /**
     * @notice Owner can fund the contract with reward tokens.
     * The supplied `reward` amount is transferred from the owner to the vault.
     */
    function notifyRewardAmount(uint256 reward) external onlyOwner updateReward(address(0)) {
        require(rewardToken.transferFrom(msg.sender, address(this), reward), "StakingVault: funding failed");
        emit RewardAdded(reward);
        // Optionally, adjust rewardRate based on a fixed duration; omitted for simplicity.
    }

    /**
     * @notice Recover ERC20 tokens mistakenly sent to the contract, except the staking token.
     */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(stakingToken), "StakingVault: cannot withdraw staking token");
        IERC20(tokenAddress).transfer(owner, tokenAmount);
    }

    /**
     * @notice View function to get the total amount staked.
     */
    function totalStaked() external view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @notice View function to get a user's staked balance.
     */
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
}
