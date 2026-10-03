// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFlashLoanReceiver {
    function executeOperation(
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

contract MagnumDeFiNexus {
    error ZeroAddress();
    error InsufficientBalance();
    error InsufficientAllowance();
    error TransferFailed();
    error StakingNotActive();
    error InvalidTier();
    error StakeLocked();
    error NoRewardsToClaim();
    error FlashLoanFailed();
    error ReentrancyGuardTriggered();
    error InvalidFlashLoanPremium();
    error Unauthorized();

    enum StakingTier { Bronze, Silver, Gold, Platinum }

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 lastClaimTime;
        StakingTier tier;
        bool active;
    }

    struct TierMetadata {
        uint256 APY;
        uint256 lockDuration;
        uint256 earlyExitPenalty;
    }

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10**18;

    string public name = "Magnum Token";
    string public symbol = "MGMT";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    address public owner;
    bool private _locked;

    uint256 public burnFeeBps = 100;
    uint256 public treasuryFeeBps = 100;
    address public treasuryWallet;
    uint256 public flashLoanFeeBps = 30;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => Stake[]) public userStakes;
    mapping(StakingTier => TierMetadata) public tiers;

    uint256 public totalTokensBurned;
    uint256 public totalTokensStaked;
    uint256 public totalRewardsDistributed;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Staked(address indexed user, uint256 indexed stakeId, uint256 amount, StakingTier tier);
    event Unstaked(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 penaltyPaid);
    event RewardClaimed(address indexed user, uint256 indexed stakeId, uint256 reward);
    event FlashLoanExecuted(address indexed receiver, uint256 amount, uint256 premium);
    event FeesUpdated(uint256 burnFee, uint256 treasuryFee);
    event TreasuryWalletUpdated(address indexed newTreasury);

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier nonReentrant() {
        if (_locked) revert ReentrancyGuardTriggered();
        _locked = true;
        _;
        _locked = false;
    }

    constructor(address _treasury) {
        if (_treasury == address(0)) revert ZeroAddress();
        owner = msg.sender;
        treasuryWallet = _treasury;
        totalSupply = INITIAL_SUPPLY;
        _balances[msg.sender] = INITIAL_SUPPLY;

        tiers[StakingTier.Bronze] = TierMetadata({ APY: 500, lockDuration: 0, earlyExitPenalty: 500 });
        tiers[StakingTier.Silver] = TierMetadata({ APY: 800, lockDuration: 30 days, earlyExitPenalty: 1000 });
        tiers[StakingTier.Gold] = TierMetadata({ APY: 1200, lockDuration: 90 days, earlyExitPenalty: 1500 });
        tiers[StakingTier.Platinum] = TierMetadata({ APY: 2000, lockDuration: 180 days, earlyExitPenalty: 2500 });

        emit Transfer(address(0), msg.sender, INITIAL_SUPPLY);
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function allowance(address ownerAddr, address spender) external view returns (uint256) {
        return _allowances[ownerAddr][spender];
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        if (_balances[from] < value) revert InsufficientBalance();

        uint256 burnAmount = (value * burnFeeBps) / BASIS_POINTS_DIVISOR;
        uint256 treasuryAmount = (value * treasuryFeeBps) / BASIS_POINTS_DIVISOR;
        uint256 transferAmount = value - burnAmount - treasuryAmount;

        _balances[from] -= value;
        _balances[to] += transferAmount;

        emit Transfer(from, to, transferAmount);

        if (burnAmount > 0) {
            totalSupply -= burnAmount;
            totalTokensBurned += burnAmount;
            emit Transfer(from, address(0), burnAmount);
        }

        if (treasuryAmount > 0) {
            _balances[treasuryWallet] += treasuryAmount;
            emit Transfer(from, treasuryWallet, treasuryAmount);
        }
    }

    function _approve(address ownerAddr, address spender, uint256 value) internal {
        if (ownerAddr == address(0) || spender == address(0)) revert ZeroAddress();
        _allowances[ownerAddr][spender] = value;
        emit Approval(ownerAddr, spender, value);
    }

    function _spendAllowance(address ownerAddr, address spender, uint256 value) internal {
        uint256 currentAllowance = _allowances[ownerAddr][spender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) revert InsufficientAllowance();
            _approve(ownerAddr, spender, currentAllowance - value);
        }
    }

    function stakeTokens(uint256 amount, StakingTier tier) external nonReentrant {
        if (amount == 0) revert InsufficientBalance();
        if (_balances[msg.sender] < amount) revert InsufficientBalance();

        _balances[msg.sender] -= amount;
        _balances[address(this)] += amount;
        totalTokensStaked += amount;

        userStakes[msg.sender].push(Stake({
            amount: amount,
            startTime: block.timestamp,
            lastClaimTime: block.timestamp,
            tier: tier,
            active: true
        }));

        emit Staked(msg.sender, userStakes[msg.sender].length - 1, amount, tier);
        emit Transfer(msg.sender, address(this), amount);
    }

    function unstakeTokens(uint256 stakeId) external nonReentrant {
        if (stakeId >= userStakes[msg.sender].length) revert InvalidTier();
        Stake storage userStake = userStakes[msg.sender][stakeId];
        if (!userStake.active) revert StakingNotActive();

        uint256 amountToReturn = userStake.amount;
        TierMetadata memory tierMeta = tiers[userStake.tier];
        uint256 reward = calculateRewards(msg.sender, stakeId);
        
        uint256 penalty = 0;
        bool isLocked = block.timestamp < (userStake.startTime + tierMeta.lockDuration);

        if (isLocked) {
            penalty = (amountToReturn * tierMeta.earlyExitPenalty) / BASIS_POINTS_DIVISOR;
            amountToReturn -= penalty;
        }

        userStake.active = false;
        totalTokensStaked -= userStake.amount;

        _balances[address(this)] -= userStake.amount;
        _balances[msg.sender] += amountToReturn;
        emit Transfer(address(this), msg.sender, amountToReturn);

        if (penalty > 0) {
            _balances[treasuryWallet] += penalty;
            emit Transfer(address(this), treasuryWallet, penalty);
        }

        if (reward > 0) {
            totalSupply += reward;
            _balances[msg.sender] += reward;
            totalRewardsDistributed += reward;
            emit RewardClaimed(msg.sender, stakeId, reward);
            emit Transfer(address(0), msg.sender, reward);
        }

        emit Unstaked(msg.sender, stakeId, userStake.amount, penalty);
    }

    function claimRewards(uint256 stakeId) external nonReentrant {
        if (stakeId >= userStakes[msg.sender].length) revert InvalidTier();
        Stake storage userStake = userStakes[msg.sender][stakeId];
        if (!userStake.active) revert StakingNotActive();

        uint256 reward = calculateRewards(msg.sender, stakeId);
        if (reward == 0) revert NoRewardsToClaim();

        userStake.lastClaimTime = block.timestamp;
        
        totalSupply += reward;
        _balances[msg.sender] += reward;
        totalRewardsDistributed += reward;

        emit RewardClaimed(msg.sender, stakeId, reward);
        emit Transfer(address(0), msg.sender, reward);
    }

    function calculateRewards(address user, uint256 stakeId) public view returns (uint256) {
        if (stakeId >= userStakes[user].length) return 0;
        Stake memory userStake = userStakes[user][stakeId];
        if (!userStake.active) return 0;

        TierMetadata memory tierMeta = tiers[userStake.tier];
        uint256 elapsedTime = block.timestamp - userStake.lastClaimTime;
        
        uint256 reward = (userStake.amount * tierMeta.APY * elapsedTime) / (BASIS_POINTS_DIVISOR * 365 days);
        return reward;
    }

    function flashLoan(
        address receiverAddress,
        uint256 amount,
        bytes calldata params
    ) external nonReentrant {
        if (receiverAddress == address(0)) revert ZeroAddress();
        if (_balances[address(this)] < amount) revert InsufficientBalance();

        uint256 premium = (amount * flashLoanFeeBps) / BASIS_POINTS_DIVISOR;

        _balances[address(this)] -= amount;
        _balances[receiverAddress] += amount;
        emit Transfer(address(this), receiverAddress, amount);

        bool success = IFlashLoanReceiver(receiverAddress).executeOperation(
            amount,
            premium,
            msg.sender,
            params
        );
        if (!success) revert FlashLoanFailed();

        uint256 returnAmount = amount + premium;
        if (_balances[receiverAddress] < returnAmount) revert InsufficientBalance();

        _balances[receiverAddress] -= returnAmount;
        _balances[address(this)] += returnAmount;
        
        _balances[address(this)] -= premium;
        _balances[treasuryWallet] += premium;
        emit Transfer(address(this), treasuryWallet, premium);

        emit FlashLoanExecuted(receiverAddress, amount, premium);
    }

    function setFees(uint256 _burnFeeBps, uint256 _treasuryFeeBps) external onlyOwner {
        if (_burnFeeBps + _treasuryFeeBps > 1000) revert InvalidFlashLoanPremium();
        burnFeeBps = _burnFeeBps;
        treasuryFeeBps = _treasuryFeeBps;
        emit FeesUpdated(_burnFeeBps, _treasuryFeeBps);
    }

    function updateTreasuryWallet(address _newTreasury) external onlyOwner {
        if (_newTreasury == address(0)) revert ZeroAddress();
        treasuryWallet = _newTreasury;
        emit TreasuryWalletUpdated(_newTreasury);
    }

    function updateFlashLoanFee(uint256 _flashLoanFeeBps) external onlyOwner {
        if (_flashLoanFeeBps > 500) revert InvalidFlashLoanPremium();
        flashLoanFeeBps = _flashLoanFeeBps;
    }

    function getUserStakesCount(address user) external view returns (uint256) {
        return userStakes[user].length;
    }
}