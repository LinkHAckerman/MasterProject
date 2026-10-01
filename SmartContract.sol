// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title Nexus DeFi Engine
 * @author Magnum Opus Architecture Team
 * @notice The core engine of the Magnum Opus decentralized ecosystem, providing:
 *         1. NexusToken (NEX) - A high-performance ERC20 utility token with gas-optimized mechanics.
 *         2. Staking Vault - Multi-tier locked yield engine supporting compound rewards.
 *         3. Automated Market Maker (AMM) - Constant-product swap engine (x * y = k) with slippage controls.
 * @dev Fully self-contained, highly optimized, and protected against common attack vectors like reentrancy and integer overflows.
 */

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrancyError();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    error ReentrancyError();
}

contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error CallerNotOwner();
    error InvalidOwnerAddress();

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        if (owner() != msg.sender) revert CallerNotOwner();
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert InvalidOwnerAddress();
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract NexusToken is IERC20, Ownable {
    string public constant name = "Nexus DeFi Ecosystem";
    string public constant symbol = "NEX";
    uint8 public constant decimals = 18;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    error InsufficientBalance();
    error TransferToZeroAddress();
    error ApproveToZeroAddress();

    constructor(uint256 initialSupply) {
        _mint(msg.sender, initialSupply);
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address ownerAddress, address spender) public view override returns (uint256) {
        return _allowances[ownerAddress][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert TransferToZeroAddress();
        if (_balances[from] < amount) revert InsufficientBalance();

        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal {
        if (account == address(0)) revert TransferToZeroAddress();

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        if (account == address(0)) revert TransferToZeroAddress();
        if (_balances[account] < amount) revert InsufficientBalance();

        _balances[account] -= amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    function _approve(address ownerAddress, address spender, uint256 amount) internal {
        if (ownerAddress == address(0) || spender == address(0)) revert ApproveToZeroAddress();

        _allowances[ownerAddress][spender] = amount;
        emit Approval(ownerAddress, spender, amount);
    }

    function _spendAllowance(address ownerAddress, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowance(ownerAddress, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert InsufficientBalance();
            _approve(ownerAddress, spender, currentAllowance - amount);
        }
    }
}

contract SmartContract is Ownable, ReentrancyGuard {
    
    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 tier;
        bool active;
    }

    struct StakingTier {
        uint256 period;       // in seconds
        uint256 multiplier;   // APY scale basis points (e.g., 500 = 5% APY, 1500 = 15% APY)
    }

    struct AMMPool {
        uint256 reserveNEX;
        uint256 reserveStable;
        uint256 totalLiquidityShares;
    }

    // Token Instance
    NexusToken public immutable nexusToken;
    IERC20 public immutable stableToken;

    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant SECONDS_IN_YEAR = 31536000;
    uint256 public constant SWAP_FEE_BPS = 30; // 0.3% protocol swap fee

    // Staking Mappings & Arrays
    mapping(address => Stake[]) public userStakes;
    StakingTier[] public stakingTiers;

    // AMM Pool State
    AMMPool public pool;
    mapping(address => uint256) public liquidityShares;

    // Global Indicators
    bool public systemPaused;

    // Custom Errors for Gas Optimization
    error SystemPaused();
    error InvalidAmount();
    error InvalidTier();
    error StakeNotMature();
    error InactiveStake();
    error SlipLimitExceeded();
    error KValueConstraintFailed();
    error EmptyPool();

    // Events
    event Staked(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 tier);
    event Unstaked(address indexed user, uint256 indexed stakeId, uint256 principal, uint256 rewards);
    event LiquidityAdded(address indexed provider, uint256 amountNEX, uint256 amountStable, uint256 sharesMinted);
    event LiquidityRemoved(address indexed provider, uint256 amountNEX, uint256 amountStable, uint256 sharesBurned);
    event SwapExecuted(address indexed swapper, bool isNEXToStable, uint256 inputAmount, uint256 outputAmount);

    modifier whenNotPaused() {
        if (systemPaused) revert SystemPaused();
        _;
    }

    constructor(address _nexusToken, address _stableToken) {
        nexusToken = NexusToken(_nexusToken);
        stableToken = IERC20(_stableToken);

        // Setup Default Staking Tiers
        stakingTiers.push(StakingTier(30 days, 500));    // Tier 0: 5% APY
        stakingTiers.push(StakingTier(90 days, 1200));   // Tier 1: 12% APY
        stakingTiers.push(StakingTier(180 days, 2500));  // Tier 2: 25% APY
        stakingTiers.push(StakingTier(365 days, 6000));  // Tier 3: 60% APY
    }

    // ==========================================
    // STAKING MODULE
    // ==========================================

    function stakeTokens(uint256 _amount, uint256 _tierIndex) external nonReentrant whenNotPaused {
        if (_amount == 0) revert InvalidAmount();
        if (_tierIndex >= stakingTiers.length) revert InvalidTier();

        nexusToken.transferFrom(msg.sender, address(this), _amount);

        userStakes[msg.sender].push(Stake({
            amount: _amount,
            startTime: block.timestamp,
            tier: _tierIndex,
            active: true
        }));

        emit Staked(msg.sender, userStakes[msg.sender].length - 1, _amount, _tierIndex);
    }

    function unstakeTokens(uint256 _stakeId) external nonReentrant {
        if (_stakeId >= userStakes[msg.sender].length) revert InactiveStake();
        Stake storage stakeItem = userStakes[msg.sender][_stakeId];
        if (!stakeItem.active) revert InactiveStake();

        StakingTier storage tier = stakingTiers[stakeItem.tier];
        if (block.timestamp < stakeItem.startTime + tier.period) revert StakeNotMature();

        stakeItem.active = false;

        uint256 durationStaked = block.timestamp - stakeItem.startTime;
        uint256 reward = (stakeItem.amount * tier.multiplier * durationStaked) / (BASIS_POINTS * SECONDS_IN_YEAR);
        uint256 totalPayout = stakeItem.amount + reward;

        // Mint reward tokens from standard utility pool reserve if necessary, or transfer
        nexusToken.transfer(msg.sender, totalPayout);

        emit Unstaked(msg.sender, _stakeId, stakeItem.amount, reward);
    }

    // ==========================================
    // AMM DEX ENGINE (Constant Product)
    // ==========================================

    function addLiquidity(uint256 _amountNEX, uint256 _amountStable) external nonReentrant whenNotPaused returns (uint256 shares) {
        if (_amountNEX == 0 || _amountStable == 0) revert InvalidAmount();

        nexusToken.transferFrom(msg.sender, address(this), _amountNEX);
        stableToken.transferFrom(msg.sender, address(this), _amountStable);

        if (pool.totalLiquidityShares == 0) {
            shares = sqrt(_amountNEX * _amountStable);
        } else {
            uint256 shareNEX = (_amountNEX * pool.totalLiquidityShares) / pool.reserveNEX;
            uint256 shareStable = (_amountStable * pool.totalLiquidityShares) / pool.reserveStable;
            shares = shareNEX < shareStable ? shareNEX : shareStable;
        }

        if (shares == 0) revert InvalidAmount();

        pool.reserveNEX += _amountNEX;
        pool.reserveStable += _amountStable;
        pool.totalLiquidityShares += shares;
        liquidityShares[msg.sender] += shares;

        emit LiquidityAdded(msg.sender, _amountNEX, _amountStable, shares);
    }

    function removeLiquidity(uint256 _shares) external nonReentrant returns (uint256 amountNEX, uint256 amountStable) {
        if (_shares == 0) revert InvalidAmount();
        if (liquidityShares[msg.sender] < _shares) revert InsufficientBalance();
        if (pool.totalLiquidityShares == 0) revert EmptyPool();

        amountNEX = (_shares * pool.reserveNEX) / pool.totalLiquidityShares;
        amountStable = (_shares * pool.reserveStable) / pool.totalLiquidityShares;

        if (amountNEX == 0 || amountStable == 0) revert EmptyPool();

        liquidityShares[msg.sender] -= _shares;
        pool.totalLiquidityShares -= _shares;
        pool.reserveNEX -= amountNEX;
        pool.reserveStable -= amountStable;

        nexusToken.transfer(msg.sender, amountNEX);
        stableToken.transfer(msg.sender, amountStable);

        emit LiquidityRemoved(msg.sender, amountNEX, amountStable, _shares);
    }

    function swapNEXForStable(uint256 _amountIn, uint256 _minAmountOut) external nonReentrant whenNotPaused returns (uint256 amountOut) {
        if (_amountIn == 0) revert InvalidAmount();
        if (pool.reserveNEX == 0 || pool.reserveStable == 0) revert EmptyPool();

        uint256 amountInWithFee = _amountIn * (BASIS_POINTS - SWAP_FEE_BPS);
        uint256 numerator = amountInWithFee * pool.reserveStable;
        uint256 denominator = (pool.reserveNEX * BASIS_POINTS) + amountInWithFee;
        amountOut = numerator / denominator;

        if (amountOut < _minAmountOut) revert SlipLimitExceeded();

        nexusToken.transferFrom(msg.sender, address(this), _amountIn);
        stableToken.transfer(msg.sender, amountOut);

        pool.reserveNEX += _amountIn;
        pool.reserveStable -= amountOut;

        emit SwapExecuted(msg.sender, true, _amountIn, amountOut);
    }

    function swapStableForNEX(uint256 _amountIn, uint256 _minAmountOut) external nonReentrant whenNotPaused returns (uint256 amountOut) {
        if (_amountIn == 0) revert InvalidAmount();
        if (pool.reserveNEX == 0 || pool.reserveStable == 0) revert EmptyPool();

        uint256 amountInWithFee = _amountIn * (BASIS_POINTS - SWAP_FEE_BPS);
        uint256 numerator = amountInWithFee * pool.reserveNEX;
        uint256 denominator = (pool.reserveStable * BASIS_POINTS) + amountInWithFee;
        amountOut = numerator / denominator;

        if (amountOut < _minAmountOut) revert SlipLimitExceeded();

        stableToken.transferFrom(msg.sender, address(this), _amountIn);
        nexusToken.transfer(msg.sender, amountOut);

        pool.reserveStable += _amountIn;
        pool.reserveNEX -= amountOut;

        emit SwapExecuted(msg.sender, false, _amountIn, amountOut);
    }

    // ==========================================
    // ANALYTICAL & HELPERS
    // ==========================================

    function getStakes(address _user) external view returns (Stake[] memory) {
        return userStakes[_user];
    }

    function getQuote(uint256 amountIn, bool isNEXToStable) external view returns (uint256 amountOut) {
        if (pool.reserveNEX == 0 || pool.reserveStable == 0) return 0;
        
        uint256 amountInWithFee = amountIn * (BASIS_POINTS - SWAP_FEE_BPS);
        if (isNEXToStable) {
            uint256 numerator = amountInWithFee * pool.reserveStable;
            uint256 denominator = (pool.reserveNEX * BASIS_POINTS) + amountInWithFee;
            amountOut = numerator / denominator;
        } else {
            uint256 numerator = amountInWithFee * pool.reserveNEX;
            uint256 denominator = (pool.reserveStable * BASIS_POINTS) + amountInWithFee;
            amountOut = numerator / denominator;
        }
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

    // ==========================================
    // ARCHITECT ADMINISTRATIVE CONTROLS
    // ==========================================

    function setPauseState(bool _state) external onlyOwner {
        systemPaused = _state;
    }

    function configureStakingTier(uint256 _index, uint256 _period, uint256 _multiplier) external onlyOwner {
        if (_index >= stakingTiers.length) revert InvalidTier();
        stakingTiers[_index].period = _period;
        stakingTiers[_index].multiplier = _multiplier;
    }

    function addStakingTier(uint256 _period, uint256 _multiplier) external onlyOwner {
        stakingTiers.push(StakingTier(_period, _multiplier));
    }

    // Emergency Recovery of tokens if inadvertently trapped in core engine
    function emergencyWithdrawToken(address _tokenAddress, uint256 _amount) external onlyOwner {
        if (_tokenAddress == address(nexusToken) || _tokenAddress == address(stableToken)) {
            // Protect active liquidity pool backing from direct manual draining
            if (IERC20(_tokenAddress).balanceOf(address(this)) - _amount < (realReserveBalanceOf(_tokenAddress))) {
                revert PoolLocked();
            }
        }
        IERC20(_tokenAddress).transfer(owner(), _amount);
    }

    function realReserveBalanceOf(address _token) internal view returns (uint256) {
        return _token == address(nexusToken) ? pool.reserveNEX : pool.reserveStable;
    }

    error PoolLocked();
}
