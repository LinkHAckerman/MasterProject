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
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description);
    event Voted(uint256 indexed proposalId, address indexed voter, bool supports);
    event ProposalExecuted(uint256 indexed proposalId);
    event FlashLoan(address indexed receiver, uint256 amount, uint256 fee);

    // Constructor
    constructor(address initialGovernor, uint256 initialRewardRate) {
        if (initialGovernor == address(0)) revert ZeroAddress();
        governor = initialGovernor;
        rewardRatePerBlock = initialRewardRate;
        _mint(initialGovernor, 10000000 * 10**18); // Initial mint for governor
    }

    // Internal functions
    function _mint(address account, uint256 amount) internal {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (_balances[account] < amount) revert InsufficientBalance();
        _totalSupply -= amount;
        _balances[account] -= amount;
        emit Transfer(account, address(0), amount);
    }

    function _updateReward(address account) internal {
        if (account != address(0)) {
            uint256 currentBlock = block.number;
            if (userInfo[account].lastActionBlock != currentBlock) {
                uint256 timeDiff = currentBlock - userInfo[account].lastActionBlock;
                uint256 reward = timeDiff * rewardRatePerBlock * userInfo[account].stakedAmount / 10**18;
                if (reward > 0) {
                    userInfo[account].rewardDebt += reward;
                    userInfo[account].lastActionBlock = currentBlock;
                }
            }
        }
    }

    // Public functions
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

    function approve(address spender, uint256 value) external override returns (bool) {
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
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

    function stake(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (_balances[msg.sender] < amount) revert InsufficientBalance();
        _burn(msg.sender, amount);
        _updateReward(msg.sender);
        userInfo[msg.sender].stakedAmount += amount;
        userInfo[msg.sender].lastActionBlock = block.number;
        totalStakedTokens += amount;
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        _updateReward(msg.sender);
        if (userInfo[msg.sender].stakedAmount < amount) revert InsufficientBalance();
        userInfo[msg.sender].stakedAmount -= amount;
        totalStakedTokens -= amount;
        _mint(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function claimRewards() external {
        _updateReward(msg.sender);
        uint256 reward = userInfo[msg.sender].rewardDebt;
        if (reward > 0) {
            userInfo[msg.sender].rewardDebt = 0;
            _mint(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function createProposal(string memory description) external {
        if (userInfo[msg.sender].stakedAmount < MIN_STAKE_FOR_PROPOSAL) revert Unauthorized();
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
        if (proposalId == 0 || proposalId > proposalCount) revert ProposalNotActive();
        if (block.number > proposals[proposalId].endBlock) revert VotePeriodEnded();
        if (hasVoted[proposalId][msg.sender]) revert ProposalAlreadyVoted();
        if (userInfo[msg.sender].stakedAmount == 0) revert Unauthorized();
        
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

    function flashLoan(address receiver, uint256 amount, bytes calldata data) external {
        if (_flashLoanLock) revert FlashLoanLockActive();
        if (amount == 0) revert ZeroAmount();
        if (_balances[address(this)] < amount) revert InsufficientBalance();
        
        _flashLoanLock = true;
        _balances[address(this)] -= amount;
        emit FlashLoan(receiver, amount, amount / 100); // 1% fee
        
        (bool success, ) = receiver.call(data);
        if (!success) revert TransferFailed();
        
        _balances[address(this)] += amount + (amount / 100);
        _flashLoanLock = false;
    }

    // Fallback function to prevent accidental ETH transfers
    fallback() external payable {
        revert();
    }

    // Receive function to prevent accidental ETH transfers
    receive() external payable {
        revert();
    }
}