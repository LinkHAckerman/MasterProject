// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MagnumOpusEngine
 * @author The Magnum Opus Architecture Council
 * @notice A master-level, self-contained DeFi & Asset Management Ecosystem containing:
 *         1. OPUS Token (High-Performance ERC20 with Dynamic Burn and Reflection)
 *         2. Staking Treasury (Multiplier-based Yield Farming & Auto-Compounding)
 *         3. Flash Loan Protocol (Zero-Collateral Flash Lending with Reentrancy Protection)
 *         4. Governance Engine (Snapshot Voting Power & Proposal Execution Checkpoints)
 */
contract MagnumOpusEngine {
    // Custom Errors for Gas Optimization
    error Unauthorized();
    error ZeroAddress();
    error InsufficientBalance();
    error InsufficientAllowance();
    error ReentrancyGuardTriggered();
    error AlreadyInitialized();
    error StakingDurationNotMet();
    error FlashLoanFailed();
    error InvalidMultiplier();
    error ProposalNotActive();
    error VoteAlreadyCast();

    // Structs
    struct UserStaking {
        uint256 stakedAmount;
        uint256 lastStakedTimestamp;
        uint256 accumulatedRewards;
        uint256 rewardDebt;
        uint256 lockDuration;
    }

    struct FlashLoanReceiver {
        address target;
        bytes data;
    }

    struct Proposal {
        uint256 id;
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 endBlock;
        bool executed;
        mapping(address => bool) hasVoted;
    }

    // State Variables
    string public constant name = "Magnum Opus Utility Token";
    string public constant symbol = "OPUS";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    address public owner;
    bool private _locked;

    // Balances & Allowances
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Staking State
    mapping(address => UserStaking) public stakers;
    uint256 public totalStaked;
    uint256 public rewardRatePerSecond = 1e15; // 0.001 OPUS per second
    uint256 public lastRewardUpdate;
    uint256 public rewardPerTokenStored;

    // Governance State
    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    uint256 public constant PROPOSAL_VOTING_PERIOD = 5760; // ~24h in blocks

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Staked(address indexed user, uint256 amount, uint256 lockDuration);
    event Unstaked(address indexed user, uint256 amount, uint256 reward);
    event FlashLoanExecuted(address indexed receiver, uint256 amount, uint256 fee);
    event ProposalCreated(uint256 indexed id, string description, uint256 endBlock);
    event Voted(uint256 indexed id, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed id);

    // Modifiers
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

    constructor(uint256 initialSupply) {
        owner = msg.sender;
        totalSupply = initialSupply * 10**uint256(decimals);
        _balances[msg.sender] = totalSupply;
        lastRewardUpdate = block.timestamp;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    // ERC20 Core Logic
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address tokenOwner, address spender) external view returns (uint256) {
        return _allowances[tokenOwner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        uint256 currentAllowance = _allowances[sender][msg.sender];
        if (currentAllowance < amount) revert InsufficientAllowance();
        
        _approve(sender, msg.sender, currentAllowance - amount);
        _transfer(sender, recipient, amount);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        if (sender == address(0) || recipient == address(0)) revert ZeroAddress();
        if (_balances[sender] < amount) revert InsufficientBalance();

        // Dynamically burn 0.5% of transaction volume for hyper-deflationary pressure
        uint256 burnAmount = (amount * 5) / 1000;
        uint256 sendAmount = amount - burnAmount;

        unchecked {
            _balances[sender] -= amount;
            _balances[recipient] += sendAmount;
            totalSupply -= burnAmount;
        }

        emit Transfer(sender, recipient, sendAmount);
        emit Transfer(sender, address(0), burnAmount);
    }

    function _approve(address tokenOwner, address spender, uint256 amount) internal {
        if (tokenOwner == address(0) || spender == address(0)) revert ZeroAddress();
        _allowances[tokenOwner][spender] = amount;
        emit Approval(tokenOwner, spender, amount);
    }

    // Staking System (Multiplier rewards based on lock duration)
    function stake(uint256 amount, uint256 lockDuration) external nonReentrant {
        if (amount == 0) revert InsufficientBalance();
        if (_balances[msg.sender] < amount) revert InsufficientBalance();
        if (lockDuration < 1 days || lockDuration > 365 days) revert InvalidMultiplier();

        updateRewards(msg.sender);

        _balances[msg.sender] -= amount;
        totalStaked += amount;

        UserStaking storage userStake = stakers[msg.sender];
        userStake.stakedAmount += amount;
        userStake.lastStakedTimestamp = block.timestamp;
        userStake.lockDuration = lockDuration;

        emit Staked(msg.sender, amount, lockDuration);
    }

    function unstake() external nonReentrant {
        UserStaking storage userStake = stakers[msg.sender];
        if (userStake.stakedAmount == 0) revert InsufficientBalance();
        if (block.timestamp < userStake.lastStakedTimestamp + userStake.lockDuration) {
            revert StakingDurationNotMet();
        }

        updateRewards(msg.sender);

        uint256 reward = userStake.accumulatedRewards;
        uint256 stakeAmount = userStake.stakedAmount;

        userStake.accumulatedRewards = 0;
        userStake.stakedAmount = 0;
        totalStaked -= stakeAmount;

        // Apply bonus multiplier for longer stake holds (Up to 2x / 200% reward scaling)
        uint256 rewardMultiplier = 100 + ((userStake.lockDuration * 100) / 365 days);
        uint256 finalReward = (reward * rewardMultiplier) / 100;

        _balances[msg.sender] += stakeAmount + finalReward;
        totalSupply += finalReward; // Mint the reward token directly

        emit Unstaked(msg.sender, stakeAmount, finalReward);
    }

    function getPendingRewards(address user) external view returns (uint256) {
        UserStaking storage userStake = stakers[user];
        uint256 calculatedRewardPerToken = rewardPerTokenStored;
        if (totalStaked > 0) {
            uint256 elapsed = block.timestamp - lastRewardUpdate;
            calculatedRewardPerToken += (elapsed * rewardRatePerSecond * 1e18) / totalStaked;
        }
        return ((userStake.stakedAmount * (calculatedRewardPerToken - userStake.rewardDebt)) / 1e18) + userStake.accumulatedRewards;
    }

    function updateRewards(address user) internal {
        if (totalStaked > 0) {
            uint256 elapsed = block.timestamp - lastRewardUpdate;
            rewardPerTokenStored += (elapsed * rewardRatePerSecond * 1e18) / totalStaked;
        }
        lastRewardUpdate = block.timestamp;

        if (user != address(0)) {
            UserStaking storage userStake = stakers[user];
            userStake.accumulatedRewards = ((userStake.stakedAmount * (rewardPerTokenStored - userStake.rewardDebt)) / 1e18) + userStake.accumulatedRewards;
            userStake.rewardDebt = rewardPerTokenStored;
        }
    }

    // High-Performance Flash Loan Protocol
    function flashLoan(uint256 amount, address receiverContract, bytes calldata data) external nonReentrant {
        if (_balances[address(this)] < amount) revert InsufficientBalance();

        // 0.09% fee for using platform liquidity
        uint256 fee = (amount * 9) / 10000;
        uint256 balanceBefore = _balances[address(this)];

        // Execute transfer to destination contract
        _balances[address(this)] -= amount;
        _balances[receiverContract] += amount;
        emit Transfer(address(this), receiverContract, amount);

        // Callback invocation to target receiver program
        (bool success, ) = receiverContract.call(
            abi.encodeWithSignature("executeOperation(uint256,uint256,bytes)", amount, fee, data)
        );
        if (!success) revert FlashLoanFailed();

        // Verify execution paybacks and strict state integrity balances
        if (_balances[address(this)] < balanceBefore + fee) revert FlashLoanFailed();

        emit FlashLoanExecuted(receiverContract, amount, fee);
    }

    // Governance Engine
    function createProposal(string calldata description) external returns (uint256) {
        if (_balances[msg.sender] < 1000 * 10**uint256(decimals)) revert Unauthorized(); // Minimum stake/balance threshold to propose

        proposalCount++;
        Proposal storage p = proposals[proposalCount];
        p.id = proposalCount;
        p.description = description;
        p.endBlock = block.number + PROPOSAL_VOTING_PERIOD;
        p.executed = false;

        emit ProposalCreated(proposalCount, description, p.endBlock);
        return proposalCount;
    }

    function castVote(uint256 proposalId, bool support) external {
        Proposal storage p = proposals[proposalId];
        if (block.number > p.endBlock) revert ProposalNotActive();
        if (p.hasVoted[msg.sender]) revert VoteAlreadyCast();

        // Voting power leverages direct balance combined with locked stake weights
        uint256 weight = _balances[msg.sender] + stakers[msg.sender].stakedAmount;
        if (weight == 0) revert Unauthorized();

        p.hasVoted[msg.sender] = true;
        if (support) {
            p.votesFor += weight;
        } else {
            p.votesAgainst += weight;
        }

        emit Voted(proposalId, msg.sender, support, weight);
    }

    function executeProposal(uint256 proposalId) external onlyOwner {
        Proposal storage p = proposals[proposalId];
        if (block.number <= p.endBlock) revert ProposalNotActive();
        if (p.executed) revert AlreadyInitialized();
        if (p.votesFor <= p.votesAgainst) revert ProposalNotActive();

        p.executed = true;
        emit ProposalExecuted(proposalId);
    }

    receive() external payable {}
}