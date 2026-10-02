// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFlashLoanReceiver
 * @notice Interface for contracts utilizing the Magnum Opus Flash Loan service.
 */
interface IFlashLoanReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

/**
 * @title IERC20
 * @notice Interface for standard ERC20 operations.
 */
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @title MagnumOpusNexus
 * @notice Central coordination hub containing AMM, Staking, Flash Loans, and Governance.
 */
contract MagnumOpusNexus {
    // Custom Errors for optimized gas footprint
    error ZeroAddress();
    error InsufficientBalance();
    error InsufficientAllowance();
    error ReentrancyGuardTriggered();
    error ContractPaused();
    error IdenticalAddresses();
    error InsufficientLiquidity();
    error InsufficientOutputAmount();
    error InvalidKValue();
    error FlashLoanFailed();
    error Unauthorized();
    error ProposalNotActive();
    error AlreadyVoted();
    error VotingClosed();
    error ExecuteFailed();

    // Reentrancy and Pause States
    uint8 private constant _NOT_ENTERED = 1;
    uint8 private constant _ENTERED = 2;
    uint8 private _status = _NOT_ENTERED;
    bool public isPaused;
    address public owner;

    // Token instances for the native AMM pair
    IERC20 public tokenA;
    IERC20 public tokenB;

    // AMM Pool balances and total LP shares
    uint256 public reserveA;
    uint256 public reserveB;
    uint256 public totalLPShares;
    mapping(address => uint256) public lpSharesOf;

    // Oracle pricing tracking
    uint256 public priceCumulativeA;
    uint256 public priceCumulativeB;
    uint256 public lastBlockTimestamp;

    // Staking parameters
    uint256 public rewardRatePerBlock = 1e18; // 1 standard reward token unit per block
    uint256 public lastRewardBlock;
    uint256 public accRewardPerShare;
    mapping(address => uint256) public stakedLPShares;
    mapping(address => uint256) public rewardDebt;

    // Flash Loan state
    uint256 public flashLoanFeeBps = 9; // 0.09% fee (9 bps)

    // Governance
    struct Proposal {
        uint256 id;
        string description;
        address targetContract;
        bytes executeData;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startBlock;
        uint256 endBlock;
        bool executed;
    }
    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public proposalVotes;
    uint256 public votingPeriodBlocks = 1000;
    uint256 public proposalThreshold = 1000 * 1e18; // Requires 1000 governance tokens to propose

    // Mock Governance Token (OPUS) minted directly inside contract for simulation or gas savings
    string public constant name = "Magnum Opus Governance Token";
    string public constant symbol = "OPUS";
    uint8 public constant decimals = 18;
    uint256 public totalGovernanceSupply;
    mapping(address => uint256) public governanceBalanceOf;
    mapping(address => mapping(address => uint256)) public governanceAllowance;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event TokenSwap(address indexed sender, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);
    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpTokens);
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpTokens);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event FlashLoanExecuted(address indexed receiver, address asset, uint256 amount, uint256 fee);
    event ProposalCreated(uint256 indexed proposalId, string description, address target, bytes data);
    event VoteCast(address indexed voter, uint256 indexed proposalId, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);

    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrancyGuardTriggered();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (isPaused) revert ContractPaused();
        _;
    }

    constructor(address _tokenA, address _tokenB) {
        if (_tokenA == address(0) || _tokenB == address(0)) revert ZeroAddress();
        if (_tokenA == _tokenB) revert IdenticalAddresses();
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        owner = msg.sender;
        lastBlockTimestamp = block.timestamp;
        lastRewardBlock = block.number;
    }

    // --- Governance Token Native Logic ---
    function mintGovernanceToken(address to, uint256 amount) public onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        totalGovernanceSupply += amount;
        governanceBalanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transferGovernance(address to, uint256 amount) external returns (bool) {
        if (to == address(0)) revert ZeroAddress();
        if (governanceBalanceOf[msg.sender] < amount) revert InsufficientBalance();
        governanceBalanceOf[msg.sender] -= amount;
        governanceBalanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    // --- AMM CORE CORE LOGIC ---
    function _updateCumulativePrices() private {
        uint256 timeElapsed = block.timestamp - lastBlockTimestamp;
        if (timeElapsed > 0 && reserveA > 0 && reserveB > 0) {
            priceCumulativeA += (reserveB * 1e18 / reserveA) * timeElapsed;
            priceCumulativeB += (reserveA * 1e18 / reserveB) * timeElapsed;
        }
        lastBlockTimestamp = block.timestamp;
    }

    function addLiquidity(uint256 amountADesired, uint256 amountBDesired) external nonReentrant whenNotPaused returns (uint256 liquidityShares) {
        if (amountADesired == 0 || amountBDesired == 0) revert InsufficientLiquidity();
        _updateCumulativePrices();

        tokenA.transferFrom(msg.sender, address(this), amountADesired);
        tokenB.transferFrom(msg.sender, address(this), amountBDesired);

        if (totalLPShares == 0) {
            liquidityShares = _sqrt(amountADesired * amountBDesired);
        } else {
            uint256 shareA = (amountADesired * totalLPShares) / reserveA;
            uint256 shareB = (amountBDesired * totalLPShares) / reserveB;
            liquidityShares = shareA < shareB ? shareA : shareB;
        }

        if (liquidityShares <= 0) revert InsufficientLiquidity();

        reserveA += amountADesired;
        reserveB += amountBDesired;
        totalLPShares += liquidityShares;
        lpSharesOf[msg.sender] += liquidityShares;

        emit LiquidityAdded(msg.sender, amountADesired, amountBDesired, liquidityShares);
    }

    function removeLiquidity(uint256 lpAmount) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        if (lpAmount == 0 || lpSharesOf[msg.sender] < lpAmount) revert InsufficientLiquidity();
        _updateCumulativePrices();

        amountA = (lpAmount * reserveA) / totalLPShares;
        amountB = (lpAmount * reserveB) / totalLPShares;

        if (amountA == 0 || amountB == 0) revert InsufficientLiquidity();

        lpSharesOf[msg.sender] -= lpAmount;
        totalLPShares -= lpAmount;
        reserveA -= amountA;
        reserveB -= amountB;

        tokenA.transfer(msg.sender, amountA);
        tokenB.transfer(msg.sender, amountB);

        emit LiquidityRemoved(msg.sender, amountA, amountB, lpAmount);
    }

    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut) external nonReentrant whenNotPaused returns (uint256 amountOut) {
        bool isTokenA = tokenIn == address(tokenA);
        if (!isTokenA && tokenIn != address(tokenB)) revert Unauthorized();

        IERC20 sourceToken = isTokenA ? tokenA : tokenB;
        IERC20 targetToken = isTokenA ? tokenB : tokenA;
        uint256 resIn = isTokenA ? reserveA : reserveB;
        uint256 resOut = isTokenA ? reserveB : reserveA;

        if (amountIn == 0) revert InsufficientOutputAmount();
        sourceToken.transferFrom(msg.sender, address(this), amountIn);

        // 0.3% protocol fee
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * resOut;
        uint256 denominator = (resIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;

        if (amountOut < minAmountOut) revert InsufficientOutputAmount();

        if (isTokenA) {
            reserveA += amountIn;
            reserveB -= amountOut;
        } else { 
            reserveB += amountIn;
            reserveA -= amountOut;
        }

        _updateCumulativePrices();
        targetToken.transfer(msg.sender, amountOut);

        emit TokenSwap(msg.sender, tokenIn, amountIn, address(targetToken), amountOut);
    }

    // --- STAKING & YIELD FARMING ENGINE ---
    function updateStakingPool() public {
        if (block.number <= lastRewardBlock) return;
        if (totalLPShares == 0) {
            lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = block.number - lastRewardBlock;
        uint256 rewards = multiplier * rewardRatePerBlock;
        accRewardPerShare += (rewards * 1e12) / totalLPShares;
        lastRewardBlock = block.number;
    }

    function stake(uint256 lpAmount) external nonReentrant whenNotPaused {
        if (lpAmount == 0 || lpSharesOf[msg.sender] < lpAmount) revert InsufficientLiquidity();
        updateStakingPool();

        if (stakedLPShares[msg.sender] > 0) {
            uint256 pending = ((stakedLPShares[msg.sender] * accRewardPerShare) / 1e12) - rewardDebt[msg.sender];
            if (pending > 0) {
                mintGovernanceToken(msg.sender, pending);
                emit RewardClaimed(msg.sender, pending);
            }
        }

        lpSharesOf[msg.sender] -= lpAmount;
        stakedLPShares[msg.sender] += lpAmount;
        rewardDebt[msg.sender] = (stakedLPShares[msg.sender] * accRewardPerShare) / 1e12;

        emit Staked(msg.sender, lpAmount);
    }

    function unstake(uint256 lpAmount) external nonReentrant {
        if (lpAmount == 0 || stakedLPShares[msg.sender] < lpAmount) revert InsufficientLiquidity();
        updateStakingPool();

        uint256 pending = ((stakedLPShares[msg.sender] * accRewardPerShare) / 1e12) - rewardDebt[msg.sender];
        if (pending > 0) {
            mintGovernanceToken(msg.sender, pending);
            emit RewardClaimed(msg.sender, pending);
        }

        stakedLPShares[msg.sender] -= lpAmount;
        lpSharesOf[msg.sender] += lpAmount;
        rewardDebt[msg.sender] = (stakedLPShares[msg.sender] * accRewardPerShare) / 1e12;

        emit Unstaked(msg.sender, lpAmount);
    }

    // --- HIGH-PERFORMANCE FLASH LOAN SYSTEM ---
    function flashLoan(address asset, uint256 amount, bytes calldata params) external nonReentrant whenNotPaused {
        bool isTokenA = asset == address(tokenA);
        if (!isTokenA && asset != address(tokenB)) revert Unauthorized();

        IERC20 targetAsset = isTokenA ? tokenA : tokenB;
        uint256 currentReserve = isTokenA ? reserveA : reserveB;
        if (amount > currentReserve) revert InsufficientLiquidity();

        uint256 fee = (amount * flashLoanFeeBps) / 10000;
        uint256 balanceBefore = targetAsset.balanceOf(address(this));

        targetAsset.transfer(msg.sender, amount);

        if (!IFlashLoanReceiver(msg.sender).executeOperation(asset, amount, fee, msg.sender, params)) {
            revert FlashLoanFailed();
        }

        uint256 balanceAfter = targetAsset.balanceOf(address(this));
        if (balanceAfter < balanceBefore + fee) revert InsufficientBalance();

        if (isTokenA) {
            reserveA = balanceAfter;
        } else {
            reserveB = balanceAfter;
        }

        emit FlashLoanExecuted(msg.sender, asset, amount, fee);
    }

    // --- DECENTRALIZED GOVERNANCE ENGINE ---
    function propose(string calldata description, address target, bytes calldata executeData) external returns (uint256) {
        if (governanceBalanceOf[msg.sender] < proposalThreshold) revert Unauthorized();

        proposalCount++;
        Proposal storage newProposal = proposals[proposalCount];
        newProposal.id = proposalCount;
        newProposal.description = description;
        newProposal.targetContract = target;
        newProposal.executeData = executeData;
        newProposal.startBlock = block.number;
        newProposal.endBlock = block.number + votingPeriodBlocks;
        newProposal.executed = false;

        emit ProposalCreated(proposalCount, description, target, executeData);
        return proposalCount;
    }

    function castVote(uint256 proposalId, bool support) external {
        Proposal storage prop = proposals[proposalId];
        if (block.number < prop.startBlock || block.number > prop.endBlock) revert VotingClosed();
        if (proposalVotes[proposalId][msg.sender]) revert AlreadyVoted();

        uint256 weight = governanceBalanceOf[msg.sender];
        if (weight == 0) revert Unauthorized();

        if (support) {
            prop.forVotes += weight;
        } else {
            prop.againstVotes += weight;
        }

        proposalVotes[proposalId][msg.sender] = true;
        emit VoteCast(msg.sender, proposalId, support, weight);
    }

    function executeProposal(uint256 proposalId) external nonReentrant payable {
        Proposal storage prop = proposals[proposalId];
        if (block.number <= prop.endBlock) revert ProposalNotActive();
        if (prop.executed) revert AlreadyVoted();
        if (prop.forVotes <= prop.againstVotes) revert ExecuteFailed();

        prop.executed = true;

        (bool success, ) = prop.targetContract.call{value: msg.value}(prop.executeData);
        if (!success) revert ExecuteFailed();

        emit ProposalExecuted(proposalId);
    }

    // --- EMERGENCY SWITCHES ---
    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    function changeOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    // --- MATHEMATICAL HELPERS ---
    function _sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}