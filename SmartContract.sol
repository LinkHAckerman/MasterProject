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

    // Events
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event ProposalCreated(uint256 indexed id, address indexed proposer, string description);
    event Voted(uint256 indexed id, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed id);

    modifier nonReentrant() {
        if (_reentrancyStatus == REENTRANCY_ENTERED) revert ReentrancyError();
        _reentrancyStatus = REENTRANCY_ENTERED;
        _;
        _reentrancyStatus = REENTRANCY_NOT_ENTERED;
    }

    modifier onlyGovernor() {
        if (msg.sender != governor) revert Unauthorized();
        _;
    }

    constructor(uint256 initialSupply, uint256 _rewardRate) {
        if (initialSupply == 0) revert ZeroAmount();
        governor = msg.sender;
        rewardRatePerBlock = _rewardRate;
        lastRewardBlock = block.number;
        _mint(msg.sender, initialSupply);
    }

    // --- ERC-20 Ledger Actions ---

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value);
        return true;
    }

    // --- Yield Farm & Staking Engine ---

    /**
     * @notice Compiles real-time block latency and updates the global pool share index.
     */
    function updatePool() public {
        if (block.number <= lastRewardBlock) return;
        if (totalStakedTokens == 0) {
            lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = block.number - lastRewardBlock;
        uint256 tokenReward = multiplier * rewardRatePerBlock;
        accRewardPerShare += (tokenReward * 1e12) / totalStakedTokens;
        lastRewardBlock = block.number;
    }

    /**
     * @notice Staking portal allowing users to commit MOPUS tokens and harvest compound interest.
     */
    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        if (user.stakedAmount > 0) {
            uint256 pending = ((user.stakedAmount * accRewardPerShare) / 1e12) - user.rewardDebt;
            if (pending > 0) {
                _mint(msg.sender, pending);
                emit RewardClaimed(msg.sender, pending);
            }
        }

        // Record action height to mitigate instant-withdraw flash-loans
        user.lastActionBlock = block.number;

        _transfer(msg.sender, address(this), amount);
        
        user.stakedAmount += amount;
        totalStakedTokens += amount;
        user.rewardDebt = (user.stakedAmount * accRewardPerShare) / 1e12;

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Unstake assets and claim generated rewards.
     */
    function unstake(uint256 amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        if (user.stakedAmount < amount) revert InsufficientBalance();
        if (amount == 0) revert ZeroAmount();
        
        // Safety gate checking block state
        if (user.lastActionBlock == block.number) revert FlashLoanLockActive();

        updatePool();

        uint256 pending = ((user.stakedAmount * accRewardPerShare) / 1e12) - user.rewardDebt;
        if (pending > 0) {
            _mint(msg.sender, pending);
            emit RewardClaimed(msg.sender, pending);
        }

        user.stakedAmount -= amount;
        totalStakedTokens -= amount;
        user.rewardDebt = (user.stakedAmount * accRewardPerShare) / 1e12;

        _transfer(address(this), msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Claims rewards without changing staked principal amount.
     */
    function claimRewards() external nonReentrant {
        updatePool();
        UserInfo storage user = userInfo[msg.sender];
        uint256 pending = ((user.stakedAmount * accRewardPerShare) / 1e12) - user.rewardDebt;
        if (pending == 0) revert ZeroAmount();

        user.rewardDebt = (user.stakedAmount * accRewardPerShare) / 1e12;
        _mint(msg.sender, pending);
        emit RewardClaimed(msg.sender, pending);
    }

    /**
     * @notice Evaluates pending rewards live.
     */
    function pendingRewards(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 _accRewardPerShare = accRewardPerShare;
        if (block.number > lastRewardBlock && totalStakedTokens != 0) {
            uint256 multiplier = block.number - lastRewardBlock;
            uint256 tokenReward = multiplier * rewardRatePerBlock;
            _accRewardPerShare += (tokenReward * 1e12) / totalStakedTokens;
        }
        return ((user.stakedAmount * _accRewardPerShare) / 1e12) - user.rewardDebt;
    }

    // --- Fully On-Chain Governance Stack ---

    /**
     * @notice Proposes a dynamic protocol upgrade or parameter pivot.
     */
    function propose(string calldata description) external returns (uint256) {
        if (userInfo[msg.sender].stakedAmount < MIN_STAKE_FOR_PROPOSAL) revert Unauthorized();
        
        uint256 proposalId = ++proposalCount;
        Proposal storage newProposal = proposals[proposalId];
        newProposal.id = proposalId;
        newProposal.description = description;
        newProposal.endBlock = block.number + VOTING_PERIOD_BLOCKS;
        newProposal.proposer = msg.sender;

        emit ProposalCreated(proposalId, msg.sender, description);
        return proposalId;
    }

    /**
     * @notice Votes on an active community proposal using staked token balance weighting.
     */
    function castVote(uint256 proposalId, bool support) external {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotActive();
        if (block.number > proposal.endBlock) revert VotePeriodEnded();
        if (hasVoted[proposalId][msg.sender]) revert ProposalAlreadyVoted();

        uint256 weight = userInfo[msg.sender].stakedAmount;
        if (weight == 0) revert ZeroAmount();

        hasVoted[proposalId][msg.sender] = true;
        if (support) {
            proposal.votesFor += weight;
        } else {
            proposal.votesAgainst += weight;
        }

        emit Voted(proposalId, msg.sender, support, weight);
    }

    /**
     * @notice Executes proposal logic if quorum and absolute majority targets are passed.
     */
    function executeProposal(uint256 proposalId) external nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotActive();
        if (block.number <= proposal.endBlock) revert VotePeriodActive();
        if (proposal.executed) revert AlreadyExecuted();

        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        if (totalVotes < (totalStakedTokens * 15) / 100) revert QuorumNotMet();
        if (proposal.votesFor <= proposal.votesAgainst) revert ProposalNotActive();

        proposal.executed = true;
        
        // Dynamics adjustment: boost reward rate per block by 5.5% on successful proposal
        rewardRatePerBlock = (rewardRatePerBlock * 1055) / 1000;

        emit ProposalExecuted(proposalId);
    }

    // --- High Performance Internal Ledger Helpers ---

    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        uint256 fromBalance = _balances[from];
        if (fromBalance < value) revert InsufficientBalance();

        unchecked {
            _balances[from] = fromBalance - value;
            _balances[to] += value;
        }

        emit Transfer(from, to, value);
    }

    function _mint(address account, uint256 value) internal {
        if (account == address(0)) revert ZeroAddress();
        _totalSupply += value;
        unchecked {
            _balances[account] += value;
        }
        emit Transfer(address(0), account, value);
    }

    function _approve(address owner, address spender, uint256 value) internal {
        if (owner == address(0) || spender == address(0)) revert ZeroAddress();
        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) revert InsufficientBalance();
            unchecked {
                _approve(owner, spender, currentAllowance - value);
            }
        } 
    }

    // --- EVM Gas Optimization Engine (Yul) ---

    /**
     * @notice Yield computation utility operating directly in inline assembly context.
     * Highly specialized method bypassing compiler-inserted memory overhead.
     */
    function computeCompoundedRewardRatio(uint256 principal, uint256 blocksActive) external pure returns (uint256 finalRatio) {
        assembly {
            let linearTerm := mul(blocksActive, 100)
            let quadTerm := mul(mul(blocksActive, blocksActive), 2)
            let multiplier := add(1000000, add(linearTerm, quadTerm))
            finalRatio := div(mul(principal, multiplier), 1000000)
        }
    }
}
