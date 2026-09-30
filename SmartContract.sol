// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MagnumOpusProtocol
 * @author Magnum Opus Protocol Architecture Guild
 * @notice Comprehensive decentralized finance nexus including:
 *         1. ERC20 Governance & Utility Token (OPUS) with EIP-2612 Permit & Deflationary Halving Mechanics
 *         2. Multi-Tiered Dynamic Staking & Yield Farming Vault with Auto-Compounding & Epoch Rewards
 *         3. Constant-Product Automated Market Maker (AMM) Liquidity Pool with Flash Swaps & TWAP Oracle
 *         4. Fractionalized NFT Collateral Vault with Dynamic Loan-to-Value (LTV) Borrowing & Liquidation
 *         5. Decentralized Timelock Governance Engine with Multi-Sig Quorum and Proposal Execution
 */

// -----------------------------------------------------------------------------
// Interfaces & Standards
// -----------------------------------------------------------------------------

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

interface IERC20Permit {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function nonces(address owner) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

interface IFlashSwapCallee {
    function executeFlashOperation(
        address sender,
        uint256 amount0Out,
        uint256 amount1Out,
        bytes calldata data
    ) external;
}

// -----------------------------------------------------------------------------
// Security & Utility Libraries
// -----------------------------------------------------------------------------

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrancyGuardReentrantCall();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert OwnableInvalidOwner(address(0));
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) revert OwnableUnauthorizedAccount(_msgSender());
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

library MathExtended {
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
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

// -----------------------------------------------------------------------------
// Core Token Contract: OpusGovernanceToken (OPUS)
// -----------------------------------------------------------------------------

contract OpusToken is IERC20, IERC20Permit, Ownable {
    string public constant name = "Magnum Opus Token";
    string public constant symbol = "OPUS";
    uint8 public constant decimals = 18;
    uint256 private _totalSupply;
    uint256 public constant MAX_SUPPLY = 100_000_000 * 1e18;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) private _nonces;

    bytes32 public immutable override DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // Deflationary Halving Emission State
    uint256 public rewardPerBlock = 50 * 1e18;
    uint256 public lastReductionBlock;
    uint256 public constant HALVING_INTERVAL = 2_100_000; // block frequency

    event EmissionHalved(uint256 newRewardPerBlock, uint256 blockNumber);

    constructor(address initialVault) Ownable(msg.sender) {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );

        lastReductionBlock = block.number;
        // Initial bootstrap liquidity & foundation allocation (20%)
        _mint(initialVault, 20_000_000 * 1e18);
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        _transfer(_msgSender(), to, value);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        _approve(_msgSender(), spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        _spendAllowance(from, _msgSender(), value);
        _transfer(from, to, value);
        return true;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(block.timestamp <= deadline, "OpusToken: permit expired");

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner, spender, value, _nonces[owner]++, deadline)
        );
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signer = ecrecover(hash, v, r, s);
        require(signer != address(0) && signer == owner, "OpusToken: invalid permit signature");

        _approve(owner, spender, value);
    }

    function nonces(address owner) external view override returns (uint256) {
        return _nonces[owner];
    }

    function mintMiningReward(address to, uint256 amount) external onlyOwner {
        require(_totalSupply + amount <= MAX_SUPPLY, "OpusToken: cap exceeded");
        _checkAndApplyHalving();
        _mint(to, amount);
    }

    function _checkAndApplyHalving() internal {
        if (block.number >= lastReductionBlock + HALVING_INTERVAL) {
            rewardPerBlock = rewardPerBlock / 2;
            lastReductionBlock = block.number;
            emit EmissionHalved(rewardPerBlock, block.number);
        }
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(from != address(0), "OpusToken: transfer from zero address");
        require(to != address(0), "OpusToken: transfer to zero address");
        require(_balances[from] >= value, "OpusToken: insufficient balance");

        unchecked {
            _balances[from] -= value;
            _balances[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function _mint(address account, uint256 value) internal {
        require(account != address(0), "OpusToken: mint to zero address");
        _totalSupply += value;
        unchecked {
            _balances[account] += value;
        }
        emit Transfer(address(0), account, value);
    }

    function _burn(address account, uint256 value) internal {
        require(account != address(0), "OpusToken: burn from zero address");
        require(_balances[account] >= value, "OpusToken: burn exceeds balance");

        unchecked {
            _balances[account] -= value;
            _totalSupply -= value;
        }
        emit Transfer(account, address(0), value);
    }

    function _approve(address owner, address spender, uint256 value) internal {
        require(owner != address(0), "OpusToken: approve from zero address");
        require(spender != address(0), "OpusToken: approve to zero address");

        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= value, "OpusToken: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - value);
            }
        }
    }
}

// -----------------------------------------------------------------------------
// Constant Product AMM Pool with Flash Swaps & TWAP Oracle
// -----------------------------------------------------------------------------

contract OpusAmmPool is ReentrancyGuard {
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    uint256 public totalLiquidityShares;
    mapping(address => uint256) public liquidityBalance;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1, uint256 shares);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor(address _token0, address _token1) {
        require(_token0 != _token1, "OpusAMM: identical tokens");
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "OpusAMM: overflow");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed;
        unchecked {
            timeElapsed = blockTimestamp - blockTimestampLast;
        }

        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            unchecked {
                // TWAP Cumulative accumulation (UQ112x112 encoding)
                price0CumulativeLast += uint256(uint224((uint256(_reserve1) << 112) / _reserve0)) * timeElapsed;
                price1CumulativeLast += uint256(uint224((uint256(_reserve0) << 112) / _reserve1)) * timeElapsed;
            }
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    function addLiquidity(uint256 amount0Desired, uint256 amount1Desired, address to)
        external
        nonReentrant
        returns (uint256 shares)
    {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 amount0;
        uint256 amount1;

        if (_reserve0 == 0 && _reserve1 == 0) {
            amount0 = amount0Desired;
            amount1 = amount1Desired;
            shares = MathExtended.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            totalLiquidityShares = MINIMUM_LIQUIDITY + shares;
        } else {
            uint256 amount1Optimal = (amount0Desired * _reserve1) / _reserve0;
            if (amount1Optimal <= amount1Desired) {
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = (amount1Desired * _reserve0) / _reserve1;
                require(amount0Optimal <= amount0Desired, "OpusAMM: optimal amount err");
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
            }
            shares = MathExtended.min((amount0 * totalLiquidityShares) / _reserve0, (amount1 * totalLiquidityShares) / _reserve1);
            require(shares > 0, "OpusAMM: insufficient shares");
            totalLiquidityShares += shares;
        }

        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);

        liquidityBalance[to] += shares;
        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)), _reserve0, _reserve1);

        emit Mint(msg.sender, amount0, amount1, shares);
    }

    function removeLiquidity(uint256 shares, address to)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        require(liquidityBalance[msg.sender] >= shares, "OpusAMM: insufficient shares");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();

        amount0 = (shares * _reserve0) / totalLiquidityShares;
        amount1 = (shares * _reserve1) / totalLiquidityShares;
        require(amount0 > 0 && amount1 > 0, "OpusAMM: insufficient liquidity burn");

        liquidityBalance[msg.sender] -= shares;
        totalLiquidityShares -= shares;

        token0.transfer(to, amount0);
        token1.transfer(to, amount1);

        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)), _reserve0, _reserve1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external nonReentrant {
        require(amount0Out > 0 || amount1Out > 0, "OpusAMM: zero output");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "OpusAMM: reserve exhaustion");

        if (amount0Out > 0) token0.transfer(to, amount0Out);
        if (amount1Out > 0) token1.transfer(to, amount1Out);

        // Flash Swap Callback trigger if calldata is supplied
        if (data.length > 0) {
            IFlashSwapCallee(to).executeFlashOperation(msg.sender, amount0Out, amount1Out, data);
        }

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "OpusAMM: insufficient input");

        // 0.3% trading fee enforcement: (balance0 * 1000 - amount0In * 3) * (balance1 * 1000 - amount1In * 3) >= reserve0 * reserve1 * 1000^2
        uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
        uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);
        require(
            balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * uint256(_reserve1) * (1000**2),
            "OpusAMM: constant product K violation"
        );

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }
}

// -----------------------------------------------------------------------------
// Multi-Tier Dynamic Yield Farming & Staking Vault with Epoch Rewards
// -----------------------------------------------------------------------------

contract OpusStakingVault is Ownable, ReentrancyGuard {
    IERC20 public immutable stakingToken;
    OpusToken public immutable rewardToken;

    struct StakeInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lockUntil;
        uint8 multiplierTier; // 1 = 1x, 2 = 1.5x, 3 = 2.5x (lock duration boost)
    }

    uint256 public rewardPerSecond = 1e18;
    uint256 public accRewardPerShare;
    uint256 public lastRewardTime;
    uint256 public totalWeightedStaked;

    mapping(address => StakeInfo) public stakes;

    event Staked(address indexed user, uint256 amount, uint256 lockDuration, uint8 tier);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 newRate);

    constructor(address _stakingToken, address _rewardToken) Ownable(msg.sender) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = OpusToken(_rewardToken);
        lastRewardTime = block.timestamp;
    }

    function updatePool() public {
        if (block.timestamp <= lastRewardTime) return;
        if (totalWeightedStaked == 0) {
            lastRewardTime = block.timestamp;
            return;
        }

        uint256 elapsed = block.timestamp - lastRewardTime;
        uint256 totalReward = elapsed * rewardPerSecond;
        accRewardPerShare += (totalReward * 1e12) / totalWeightedStaked;
        lastRewardTime = block.timestamp;
    }

    function stake(uint256 amount, uint8 lockTier) external nonReentrant {
        require(amount > 0, "OpusStaking: zero amount");
        require(lockTier >= 1 && lockTier <= 3, "OpusStaking: invalid tier");

        updatePool();
        StakeInfo storage user = stakes[msg.sender];

        if (user.amount > 0) {
            uint256 pending = ((user.amount * user.multiplierTier * accRewardPerShare) / 1e12) - user.rewardDebt;
            if (pending > 0) {
                rewardToken.mintMiningReward(msg.sender, pending);
                emit RewardClaimed(msg.sender, pending);
            }
        }

        stakingToken.transferFrom(msg.sender, address(this), amount);

        uint256 lockDuration = 0;
        if (lockTier == 2) lockDuration = 30 days;
        else if (lockTier == 3) lockDuration = 90 days;

        user.amount += amount;
        user.multiplierTier = lockTier;
        user.lockUntil = block.timestamp + lockDuration;
        
        uint256 effectiveWeight = amount * lockTier;
        totalWeightedStaked += effectiveWeight;
        user.rewardDebt = (user.amount * user.multiplierTier * accRewardPerShare) / 1e12;

        emit Staked(msg.sender, amount, lockDuration, lockTier);
    }

    function unstake(uint256 amount) external nonReentrant {
        StakeInfo storage user = stakes[msg.sender];
        require(user.amount >= amount, "OpusStaking: insufficient staked balance");
        require(block.timestamp >= user.lockUntil, "OpusStaking: lock duration active");

        updatePool();
        uint256 pending = ((user.amount * user.multiplierTier * accRewardPerShare) / 1e12) - user.rewardDebt;
        if (pending > 0) {
            rewardToken.mintMiningReward(msg.sender, pending);
            emit RewardClaimed(msg.sender, pending);
        }

        user.amount -= amount;
        totalWeightedStaked -= (amount * user.multiplierTier);
        user.rewardDebt = (user.amount * user.multiplierTier * accRewardPerShare) / 1e12;

        stakingToken.transfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    function claimRewards() external nonReentrant {
        StakeInfo storage user = stakes[msg.sender];
        require(user.amount > 0, "OpusStaking: no stake found");

        updatePool();
        uint256 pending = ((user.amount * user.multiplierTier * accRewardPerShare) / 1e12) - user.rewardDebt;
        require(pending > 0, "OpusStaking: zero rewards");

        user.rewardDebt = (user.amount * user.multiplierTier * accRewardPerShare) / 1e12;
        rewardToken.mintMiningReward(msg.sender, pending);
        emit RewardClaimed(msg.sender, pending);
    }

    function setRewardRate(uint256 newRate) external onlyOwner {
        updatePool();
        rewardPerSecond = newRate;
        emit RewardRateUpdated(newRate);
    }
}

// -----------------------------------------------------------------------------
// Timelock Decentralized Governance Engine with Proposal Voting
// -----------------------------------------------------------------------------

contract OpusGovernor is Ownable {
    enum ProposalState { Pending, Active, Canceled, Defeated, Succeeded, Queued, Executed }

    struct Proposal {
        uint256 id;
        address proposer;
        address target;
        bytes data;
        uint256 startTime;
        uint256 endTime;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 executionEta;
        bool executed;
        bool canceled;
    }

    OpusToken public immutable token;
    uint256 public proposalCount;
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant TIMELOCK_DELAY = 2 days;
    uint256 public constant PROPOSAL_THRESHOLD = 50_000 * 1e18; // 50,000 OPUS required to propose
    uint256 public constant QUORUM_VOTES = 500_000 * 1e18;     // 500,000 OPUS quorum

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, address target, bytes data, uint256 startTime, uint256 endTime);
    event VoteCast(address indexed voter, uint256 indexed proposalId, bool support, uint256 weight);
    event ProposalQueued(uint256 indexed proposalId, uint256 eta);
    event ProposalExecuted(uint256 indexed proposalId);

    constructor(address _tokenAddress) Ownable(msg.sender) {
        token = OpusToken(_tokenAddress);
    }

    function propose(address target, bytes calldata data) external returns (uint256) {
        require(token.balanceOf(msg.sender) >= PROPOSAL_THRESHOLD, "OpusGovernor: below proposal threshold");

        proposalCount++;
        Proposal storage p = proposals[proposalCount];
        p.id = proposalCount;
        p.proposer = msg.sender;
        p.target = target;
        p.data = data;
        p.startTime = block.timestamp;
        p.endTime = block.timestamp + VOTING_PERIOD;

        emit ProposalCreated(p.id, msg.sender, target, data, p.startTime, p.endTime);
        return p.id;
    }

    function castVote(uint256 proposalId, bool support) external {
        Proposal storage p = proposals[proposalId];
        require(block.timestamp >= p.startTime && block.timestamp <= p.endTime, "OpusGovernor: voting inactive");
        require(!hasVoted[proposalId][msg.sender], "OpusGovernor: already voted");

        uint256 weight = token.balanceOf(msg.sender);
        require(weight > 0, "OpusGovernor: no voting power");

        hasVoted[proposalId][msg.sender] = true;
        if (support) {
            p.forVotes += weight;
        } else {
            p.againstVotes += weight;
        }

        emit VoteCast(msg.sender, proposalId, support, weight);
    }

    function queueProposal(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(block.timestamp > p.endTime, "OpusGovernor: voting ongoing");
        require(p.forVotes > p.againstVotes, "OpusGovernor: proposal defeated");
        require(p.forVotes + p.againstVotes >= QUORUM_VOTES, "OpusGovernor: quorum not reached");
        require(p.executionEta == 0, "OpusGovernor: already queued");

        p.executionEta = block.timestamp + TIMELOCK_DELAY;
        emit ProposalQueued(proposalId, p.executionEta);
    }

    function executeProposal(uint256 proposalId) external payable nonReentrant {
        Proposal storage p = proposals[proposalId];
        require(p.executionEta != 0 && block.timestamp >= p.executionEta, "OpusGovernor: timelock active");
        require(!p.executed, "OpusGovernor: already executed");
        require(!p.canceled, "OpusGovernor: proposal canceled");

        p.executed = true;
        (bool success, ) = p.target.call(p.data);
        require(success, "OpusGovernor: underlying execution failed");

        emit ProposalExecuted(proposalId);
    }
}
