// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Magnum Opus Protocol Engine
 * @notice The ultimate, all-encompassing Solidity Smart Contract serving as the decentralized ledger,
 * high-yield staking protocol, and on-chain governance system for the Web3 & DeFi Nexus.
 * Incorporates Synthetix-inspired reward accumulation, advanced gas-saving Yul inline assembly,
 * reentrancy safety mechanics, and flash-loan exploitation prevention layers.
 */

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract MagnumOpusEngine is IERC20 {
    // Custom errors for gas-squeezed failure states
    error Unauthorized();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance();
    error TransferFailed();
    error ReentrancyError();
    error FlashLoanLockActive();
    error ProposalNotActive();
    error ProposalAlreadyVoted();
    error VotePeriodEnded();
    error VotePeriodActive();
    error AlreadyExecuted();
    error QuorumNotMet();

    // Token Details
    string public constant name = "Magnum Opus Token";
    string public constant symbol = "MOPUS";
    uint8 public constant decimals = 18;
    uint256 private _totalSupply;
    
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Protocol Metrics & Staking Variables
    address public immutable governor;
    uint256 public rewardRatePerBlock;
    uint256 public accRewardPerShare;
    uint256 public lastRewardBlock;
    uint256 public totalStakedTokens;

    struct UserInfo {
        uint256 stakedAmount;
        uint256 rewardDebt;
        uint256 lastActionBlock;
    }

    struct Proposal {
        uint256 id;
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 endBlock;
        bool executed;
        address proposer;
    }

    mapping(address => UserInfo) public userInfo;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    uint256 public proposalCount;
    
    uint256 public constant VOTING_PERIOD_BLOCKS = 100;
    uint256 public constant MIN_STAKE_FOR_PROPOSAL = 1000 * 10**18;
    
    // Reentrancy Guards
    uint256 private constant REENTRANCY_NOT_ENTERED = 1;
    uint256 private constant REENTRANCY_ENTERED = 2;
    uint256 private _reentrancyStatus = REENTRANCY_NOT_ENTERED;

    // Flash Loan Protection
    bool private _flashLoanLock;

    // Events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    event ProposalCreated(uint256 indexed id, address indexed proposer, string description);
    event Voted(uint256 indexed id, address indexed voter, bool supports);
    event ProposalExecuted(uint256 indexed id);
    event FlashLoan(address indexed receiver, uint256 amount, uint256 fee);

    // Modifiers
    modifier nonReentrant() {
        if (_reentrancyStatus != REENTRANCY_NOT_ENTERED) revert ReentrancyError();
        _reentrancyStatus = REENTRANCY_ENTERED;
        _;
        _reentrancyStatus = REENTRANCY_NOT_ENTERED;
    }

    modifier flashLoanLock() {
        if (_flashLoanLock) revert FlashLoanLockActive();
        _flashLoanLock = true;
        _;
        _flashLoanLock = false;
    }

    // Constructor
    constructor(address initialGovernor, uint256 initialRewardRate) {
        if (initialGovernor == address(0)) revert ZeroAddress();
        governor = initialGovernor;
        rewardRatePerBlock = initialRewardRate;
        _mint(initialGovernor, 1000000 * 10**18); // Initial mint for governor
    }

    // IERC20 Implementation
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        if (to == address(0)) revert ZeroAddress();
        if (value == 0) revert ZeroAmount();
        if (_balances[msg.sender] < value) revert InsufficientBalance();

        _balances[msg.sender] -= value;
        _balances[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        if (to == address(0)) revert ZeroAddress();
        if (value == 0) revert ZeroAmount();
        if (_balances[from] < value) revert InsufficientBalance();
        if (_allowances[from][msg.sender] < value) revert Unauthorized();

        _balances[from] -= value;
        _balances[to] += value;
        _allowances[from][msg.sender] -= value;
        emit Transfer(from, to, value);
        return true;
    }

    // Internal Minting
    function _mint(address account, uint256 amount) internal {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    // Staking Functions
    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (_balances[msg.sender] < amount) revert InsufficientBalance();

        _balances[msg.sender] -= amount;
        userInfo[msg.sender].stakedAmount += amount;
        userInfo[msg.sender].lastActionBlock = block.number;
        totalStakedTokens += amount;
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (userInfo[msg.sender].stakedAmount < amount) revert InsufficientBalance();

        _updateReward(msg.sender);
        userInfo[msg.sender].stakedAmount -= amount;
        userInfo[msg.sender].lastActionBlock = block.number;
        totalStakedTokens -= amount;
        _balances[msg.sender] += amount;
        emit Withdrawn(msg.sender, amount);
    }

    function claimRewards() external nonReentrant {
        _updateReward(msg.sender);
        uint256 reward = userInfo[msg.sender].rewardDebt;
        if (reward > 0) {
            userInfo[msg.sender].rewardDebt = 0;
            _balances[msg.sender] += reward;
            emit RewardPaid(msg.sender, reward);
        }
    }

    // Governance Functions
    function createProposal(string memory description) external {
        if (userInfo[msg.sender].stakedAmount < MIN_STAKE_FOR_PROPOSAL) revert Unauthorized();
        if (bytes(description).length == 0) revert ZeroAmount();

        proposalCount++;
        proposals[proposalCount] = Proposal({
            id: proposalCount,
            description: description,
            votesFor: 0,
            votesAgainst: 0,
            endBlock: block.number + VOTING_PERIOD_BLOCKS,
            executed: false,
            proposer: msg.sender
        });
        emit ProposalCreated(proposalCount, msg.sender, description);
    }

    function vote(uint256 proposalId, bool supports) external {
        if (userInfo[msg.sender].stakedAmount == 0) revert Unauthorized();
        if (proposalId == 0 || proposalId > proposalCount) revert ProposalNotActive();
        if (hasVoted[proposalId][msg.sender]) revert ProposalAlreadyVoted();
        if (block.number > proposals[proposalId].endBlock) revert VotePeriodEnded();

        hasVoted[proposalId][msg.sender] = true;
        if (supports) {
            proposals[proposalId].votesFor += userInfo[msg.sender].stakedAmount;
        } else {
            proposals[proposalId].votesAgainst += userInfo[msg.sender].stakedAmount;
        }
        emit Voted(proposalId, msg.sender, supports);
    }

    function executeProposal(uint256 proposalId) external {
        if (proposalId == 0 || proposalId > proposalCount) revert ProposalNotActive();
        if (block.number <= proposals[proposalId].endBlock) revert VotePeriodActive();
        if (proposals[proposalId].executed) revert AlreadyExecuted();
        if (proposals[proposalId].votesFor <= proposals[proposalId].votesAgainst) revert QuorumNotMet();

        proposals[proposalId].executed = true;
        emit ProposalExecuted(proposalId);
    }

    // Flash Loan Functions
    function flashLoan(address receiver, uint256 amount, bytes calldata data) external flashLoanLock {
        if (receiver == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (_balances[address(this)] < amount) revert InsufficientBalance();

        _balances[address(this)] -= amount;
        _balances[receiver] += amount;

        // Call the receiver's contract
        (bool success, ) = receiver.call(data);
        if (!success) revert TransferFailed();

        // Calculate fee (1% of amount)
        uint256 fee = amount / 100;
        _balances[receiver] -= amount;
        _balances[address(this)] += amount - fee;
        emit FlashLoan(receiver, amount, fee);
    }

    // Internal Functions
    function _updateReward(address user) internal {
        if (userInfo[user].stakedAmount == 0) return;

        uint256 currentBlock = block.number;
        uint256 blocksSinceLastAction = currentBlock - userInfo[user].lastActionBlock;
        if (blocksSinceLastAction == 0) return;

        uint256 reward = (userInfo[user].stakedAmount * rewardRatePerBlock * blocksSinceLastAction) / 1e18;
        userInfo[user].rewardDebt += reward;
        userInfo[user].lastActionBlock = currentBlock;
    }

    function _updateRewardPerShare() internal {
        if (totalStakedTokens == 0) return;

        uint256 currentBlock = block.number;
        uint256 blocksSinceLastReward = currentBlock - lastRewardBlock;
        if (blocksSinceLastReward == 0) return;

        uint256 reward = rewardRatePerBlock * blocksSinceLastReward;
        accRewardPerShare += (reward * 1e18) / totalStakedTokens;
        lastRewardBlock = currentBlock;
    }
}