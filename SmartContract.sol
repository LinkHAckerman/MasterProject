// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * ============================================================================
 * MAGNUM OPUS // Web3, DeFi, Staking, DEX, Lending & NFT Nexus Protocol
 * Complete Enterprise DeFi Infrastructure & Autonomous Financial Suite
 * ============================================================================
 */

// -----------------------------------------------------------------------------
// Custom Protocol Errors (Gas-Optimized)
// -----------------------------------------------------------------------------
error Unauthorized();
error ZeroAddress();
error ZeroAmount();
error InsufficientBalance(uint256 available, uint256 required);
error InsufficientAllowance(uint256 available, uint256 required);
error InsufficientLiquidity();
error InsufficientOutputAmount(uint256 actual, uint256 minimum);
error SlippageExceeded();
error PoolLocked();
error PositionLocked(uint256 unlockTimestamp);
error IdenticalAddresses();
error ExpiredDeadline();
error InvalidSignature();
error SignatureExpired();
error NonceMismatch();
error HealthFactorSafe(uint256 healthFactor);
error Undercollateralized(uint256 healthFactor);
error FlashLoanFailed();
error InvalidRoyaltyPercentage();
error MaxSupplyReached();
error TokenDoesNotExist();

// -----------------------------------------------------------------------------
// Common Math Library
// -----------------------------------------------------------------------------
library MagnumMath {
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x > y ? x : y;
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
// Core Access & Security Contracts
// -----------------------------------------------------------------------------
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

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) revert Unauthorized();
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != ENTERED, "ReentrancyGuard: reentrant call");
        _status = ENTERED;
        _;
        _status = NOT_ENTERED;
    }
}

abstract contract Pausable is Context {
    event Paused(address account);
    event Unpaused(address account);

    bool private _paused;

    constructor() {
        _paused = false;
    }

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

// -----------------------------------------------------------------------------
// Standard Interfaces
// -----------------------------------------------------------------------------
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

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

interface IFlashLoanReceiver {
    function executeOperation(address token, uint256 amount, uint256 fee, bytes calldata params) external returns (bool);
}

// -----------------------------------------------------------------------------
// Core Token: Magnum Opus Token (MGM)
// -----------------------------------------------------------------------------
contract MagnumToken is Context, IERC20, IERC20Metadata, Ownable {
    string private _name;
    string private _symbol;
    uint8 private constant _decimals = 18;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _minters;

    event MinterStatusChanged(address indexed minter, bool status);

    modifier onlyMinter() {
        if (!_minters[_msgSender()] && owner() != _msgSender()) revert Unauthorized();
        _;
    }

    constructor(uint256 initialSupply) Ownable(msg.sender) {
        _name = "Magnum Opus Token";
        _symbol = "MGM";
        _mint(msg.sender, initialSupply * (10 ** _decimals));
    }

    function name() public view override returns (string memory) { return _name; }
    function symbol() public view override returns (string memory) { return _symbol; }
    function decimals() public view override returns (uint8) { return _decimals; }
    function totalSupply() public view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }

    function setMinter(address minter, bool status) external onlyOwner {
        if (minter == address(0)) revert ZeroAddress();
        _minters[minter] = status;
        emit MinterStatusChanged(minter, status);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address ownerAddress, address spender) public view override returns (uint256) {
        return _allowances[ownerAddress][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert InsufficientAllowance(currentAllowance, amount);
            unchecked {
                _approve(sender, _msgSender(), currentAllowance - amount);
            }
        }
        _transfer(sender, recipient, amount);
        return true;
    }

    function mint(address account, uint256 amount) external onlyMinter {
        _mint(account, amount);
    }

    function burn(uint256 amount) external {
        _burn(_msgSender(), amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        if (sender == address(0) || recipient == address(0)) revert ZeroAddress();
        uint256 senderBalance = _balances[sender];
        if (senderBalance < amount) revert InsufficientBalance(senderBalance, amount);
        unchecked {
            _balances[sender] = senderBalance - amount;
            _balances[recipient] += amount;
        }
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        if (account == address(0)) revert ZeroAddress();
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        if (account == address(0)) revert ZeroAddress();
        uint256 accountBalance = _balances[account];
        if (accountBalance < amount) revert InsufficientBalance(accountBalance, amount);
        unchecked {
            _balances[account] = accountBalance - amount;
            _totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
    }

    function _approve(address ownerAddress, address spender, uint256 amount) internal {
        if (ownerAddress == address(0) || spender == address(0)) revert ZeroAddress();
        _allowances[ownerAddress][spender] = amount;
        emit Approval(ownerAddress, spender, amount);
    }
}

// -----------------------------------------------------------------------------
// DEX Automated Market Maker (Constant Product AMM)
// -----------------------------------------------------------------------------
contract MagnumDEXPair is ReentrancyGuard, Ownable {
    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to);
    event Sync(uint112 reserve0, uint112 reserve1);
    event FlashLoan(address indexed borrower, address indexed token, uint256 amount, uint256 fee);

    constructor(address _token0, address _token1) Ownable(msg.sender) {
        if (_token0 == _token1) revert IdenticalAddresses();
        if (_token0 == address(0) || _token1 == address(0)) revert ZeroAddress();
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _update(uint256 balance0, uint256 balance1) private {
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp % 2**32);
        emit Sync(reserve0, reserve1);
    }

    function addLiquidity(uint256 amount0Desired, uint256 amount1Desired, address to) external nonReentrant returns (uint256 liquidity) {
        IERC20(token0).transferFrom(msg.sender, address(this), amount0Desired);
        IERC20(token1).transferFrom(msg.sender, address(this), amount1Desired);

        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            liquidity = MagnumMath.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            totalSupply = MINIMUM_LIQUIDITY + liquidity;
            balanceOf[address(0)] = MINIMUM_LIQUIDITY;
        } else {
            liquidity = MagnumMath.min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
            totalSupply += liquidity;
        }

        if (liquidity == 0) revert InsufficientLiquidity();
        balanceOf[to] += liquidity;
        _update(balance0, balance1);
        emit Mint(msg.sender, amount0, amount1);
    }

    function removeLiquidity(uint256 liquidity, address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (balanceOf[msg.sender] < liquidity) revert InsufficientBalance(balanceOf[msg.sender], liquidity);
        
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 _totalSupply = totalSupply;

        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidity();

        balanceOf[msg.sender] -= liquidity;
        totalSupply -= liquidity;

        IERC20(token0).transfer(to, amount0);
        IERC20(token1).transfer(to, amount1);

        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));
        _update(balance0, balance1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to) external nonReentrant {
        if (amount0Out == 0 && amount1Out == 0) revert ZeroAmount();
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        if (amount0Out >= _reserve0 || amount1Out >= _reserve1) revert InsufficientLiquidity();

        if (amount0Out > 0) IERC20(token0).transfer(to, amount0Out);
        if (amount1Out > 0) IERC20(token1).transfer(to, amount1Out);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        if (amount0In == 0 && amount1In == 0) revert ZeroAmount();

        // 0.3% trading fee mechanism check
        uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
        uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);
        if (balance0Adjusted * balance1Adjusted < uint256(_reserve0) * uint256(_reserve1) * 1000**2) {
            revert SlippageExceeded();
        }

        _update(balance0, balance1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function flashLoan(address target, address token, uint256 amount, bytes calldata data) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (token != token0 && token != token1) revert Unauthorized();
        
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        if (balanceBefore < amount) revert InsufficientLiquidity();

        uint256 fee = (amount * 9) / 10000; // 0.09% fee
        IERC20(token).transfer(target, amount);

        bool success = IFlashLoanReceiver(target).executeOperation(token, amount, fee, data);
        if (!success) revert FlashLoanFailed();

        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        if (balanceAfter < balanceBefore + fee) revert FlashLoanFailed();

        (uint256 balance0, uint256 balance1) = (IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
        _update(balance0, balance1);
        emit FlashLoan(target, token, amount, fee);
    }
}

// -----------------------------------------------------------------------------
// Multi-Tier Yield Staking Engine
// -----------------------------------------------------------------------------
contract MagnumStakingVault is ReentrancyGuard, Pausable, Ownable {
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    struct Tier {
        uint256 lockDuration;
        uint256 multiplierBps; // 10000 = 1.0x
        bool active;
    }

    struct StakePosition {
        uint256 amount;
        uint256 tierId;
        uint256 startTime;
        uint256 rewardDebt;
        uint256 unlockTime;
    }

    mapping(uint256 => Tier) public tiers;
    uint256 public nextTierId;

    mapping(address => StakePosition[]) public userPositions;
    uint256 public rewardPerSecond;
    uint256 public lastRewardTime;
    uint256 public accRewardPerShare;
    uint256 public totalStakedWeighted;

    event Staked(address indexed user, uint256 indexed positionId, uint256 amount, uint256 tierId);
    event Unstaked(address indexed user, uint256 indexed positionId, uint256 amount, uint256 reward);
    event RewardHarvested(address indexed user, uint256 indexed positionId, uint256 amount);
    event TierAdded(uint256 indexed tierId, uint256 lockDuration, uint256 multiplierBps);

    constructor(address _stakingToken, address _rewardToken, uint256 _rewardPerSecond) Ownable(msg.sender) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardPerSecond = _rewardPerSecond;
        lastRewardTime = block.timestamp;

        _addTier(0, 10000);        // Flexible: 1x
        _addTier(30 days, 12500);  // 30 Days: 1.25x
        _addTier(90 days, 17500);  // 90 Days: 1.75x
        _addTier(365 days, 30000); // 1 Year: 3x
    }

    function _addTier(uint256 duration, uint256 multiplierBps) private {
        tiers[nextTierId] = Tier(duration, multiplierBps, true);
        emit TierAdded(nextTierId, duration, multiplierBps);
        nextTierId++;
    }

    function addTier(uint256 duration, uint256 multiplierBps) external onlyOwner {
        _addTier(duration, multiplierBps);
    }

    function updatePool() public {
        if (block.timestamp <= lastRewardTime) return;
        if (totalStakedWeighted == 0) {
            lastRewardTime = block.timestamp;
            return;
        }
        uint256 elapsed = block.timestamp - lastRewardTime;
        uint256 rewardAmount = elapsed * rewardPerSecond;
        accRewardPerShare += (rewardAmount * 1e12) / totalStakedWeighted;
        lastRewardTime = block.timestamp;
    }

    function stake(uint256 amount, uint256 tierId) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        Tier memory tier = tiers[tierId];
        if (!tier.active) revert Unauthorized();

        updatePool();
        stakingToken.transferFrom(msg.sender, address(this), amount);

        uint256 weightedAmount = (amount * tier.multiplierBps) / 10000;
        totalStakedWeighted += weightedAmount;

        uint256 unlockTime = block.timestamp + tier.lockDuration;
        uint256 rewardDebt = (weightedAmount * accRewardPerShare) / 1e12;

        userPositions[msg.sender].push(StakePosition({
            amount: amount,
            tierId: tierId,
            startTime: block.timestamp,
            rewardDebt: rewardDebt,
            unlockTime: unlockTime
        }));

        emit Staked(msg.sender, userPositions[msg.sender].length - 1, amount, tierId);
    }

    function harvest(uint256 positionId) public nonReentrant {
        if (positionId >= userPositions[msg.sender].length) revert Unauthorized();
        updatePool();

        StakePosition storage pos = userPositions[msg.sender][positionId];
        Tier memory tier = tiers[pos.tierId];
        uint256 weightedAmount = (pos.amount * tier.multiplierBps) / 10000;
        
        uint256 accumulated = (weightedAmount * accRewardPerShare) / 1e12;
        uint256 pending = accumulated > pos.rewardDebt ? accumulated - pos.rewardDebt : 0;

        if (pending > 0) {
            pos.rewardDebt = accumulated;
            rewardToken.transfer(msg.sender, pending);
            emit RewardHarvested(msg.sender, positionId, pending);
        }
    }

    function unstake(uint256 positionId) external nonReentrant {
        if (positionId >= userPositions[msg.sender].length) revert Unauthorized();
        StakePosition storage pos = userPositions[msg.sender][positionId];
        if (block.timestamp < pos.unlockTime) revert PositionLocked(pos.unlockTime);

        harvest(positionId);

        uint256 amount = pos.amount;
        Tier memory tier = tiers[pos.tierId];
        uint256 weightedAmount = (amount * tier.multiplierBps) / 10000;
        totalStakedWeighted -= weightedAmount;

        // Move last position to current slot
        uint256 lastIdx = userPositions[msg.sender].length - 1;
        if (positionId != lastIdx) {
            userPositions[msg.sender][positionId] = userPositions[msg.sender][lastIdx];
        }
        userPositions[msg.sender].pop();

        stakingToken.transfer(msg.sender, amount);
        emit Unstaked(msg.sender, positionId, amount, 0);
    }

    function getUserPositionCount(address user) external view returns (uint256) {
        return userPositions[user].length;
    }
}

// -----------------------------------------------------------------------------
// Lending, Borrowing & Collateral Engine
// -----------------------------------------------------------------------------
contract MagnumLendingPool is ReentrancyGuard, Pausable, Ownable {
    IERC20 public immutable collateralToken;
    IERC20 public immutable borrowToken;

    uint256 public constant COLLATERAL_FACTOR = 7500; // 75% LTV
    uint256 public constant LIQUIDATION_THRESHOLD = 8000; // 80%
    uint256 public constant LIQUIDATION_DISCOUNT = 1000; // 10%

    struct UserAccount {
        uint256 collateralBalance;
        uint256 borrowedAmount;
        uint256 lastInterestBlock;
    }

    mapping(address => UserAccount) public accounts;
    uint256 public totalCollateral;
    uint256 public totalBorrows;
    uint256 public oraclePriceRatio; // Collateral price in BorrowToken units (scaled 1e18)

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(address indexed borrower, address indexed liquidator, uint256 repayAmount, uint256 seizedCollateral);
    event OracleUpdated(uint256 newPriceRatio);

    constructor(address _collateralToken, address _borrowToken, uint256 _initialOraclePriceRatio) Ownable(msg.sender) {
        collateralToken = IERC20(_collateralToken);
        borrowToken = IERC20(_borrowToken);
        oraclePriceRatio = _initialOraclePriceRatio;
    }

    function setOraclePriceRatio(uint256 _priceRatio) external onlyOwner {
        if (_priceRatio == 0) revert ZeroAmount();
        oraclePriceRatio = _priceRatio;
        emit OracleUpdated(_priceRatio);
    }

    function getHealthFactor(address user) public view returns (uint256) {
        UserAccount memory acc = accounts[user];
        if (acc.borrowedAmount == 0) return type(uint256).max;

        uint256 collateralValueInBorrow = (acc.collateralBalance * oraclePriceRatio) / 1e18;
        uint256 maxBorrowAllowed = (collateralValueInBorrow * LIQUIDATION_THRESHOLD) / 10000;
        return (maxBorrowAllowed * 1e18) / acc.borrowedAmount;
    }

    function depositCollateral(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        collateralToken.transferFrom(msg.sender, address(this), amount);
        accounts[msg.sender].collateralBalance += amount;
        totalCollateral += amount;
        emit CollateralDeposited(msg.sender, amount);
    }

    function withdrawCollateral(uint256 amount) external nonReentrant {
        UserAccount storage acc = accounts[msg.sender];
        if (acc.collateralBalance < amount) revert InsufficientBalance(acc.collateralBalance, amount);

        acc.collateralBalance -= amount;
        totalCollateral -= amount;

        if (acc.borrowedAmount > 0) {
            uint256 hf = getHealthFactor(msg.sender);
            if (hf < 1e18) revert Undercollateralized(hf);
        }

        collateralToken.transfer(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, amount);
    }

    function borrow(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        UserAccount storage acc = accounts[msg.sender];

        uint256 collateralValueInBorrow = (acc.collateralBalance * oraclePriceRatio) / 1e18;
        uint256 maxBorrow = (collateralValueInBorrow * COLLATERAL_FACTOR) / 10000;

        if (acc.borrowedAmount + amount > maxBorrow) revert Undercollateralized(getHealthFactor(msg.sender));

        acc.borrowedAmount += amount;
        totalBorrows += amount;
        borrowToken.transfer(msg.sender, amount);
        emit Borrowed(msg.sender, amount);
    }

    function repay(uint256 amount) external nonReentrant {
        UserAccount storage acc = accounts[msg.sender];
        if (acc.borrowedAmount == 0) revert ZeroAmount();

        uint256 repayAmount = amount > acc.borrowedAmount ? acc.borrowedAmount : amount;
        borrowToken.transferFrom(msg.sender, address(this), repayAmount);

        acc.borrowedAmount -= repayAmount;
        totalBorrows -= repayAmount;
        emit Repaid(msg.sender, repayAmount);
    }

    function liquidate(address borrower, uint256 repayAmount) external nonReentrant {
        uint256 hf = getHealthFactor(borrower);
        if (hf >= 1e18) revert HealthFactorSafe(hf);

        UserAccount storage acc = accounts[borrower];
        if (repayAmount > acc.borrowedAmount) revert InsufficientBalance(acc.borrowedAmount, repayAmount);

        borrowToken.transferFrom(msg.sender, address(this), repayAmount);
        acc.borrowedAmount -= repayAmount;
        totalBorrows -= repayAmount;

        // Seize collateral with liquidation bonus discount
        uint256 collateralValueSeizedInBorrow = (repayAmount * (10000 + LIQUIDATION_DISCOUNT)) / 10000;
        uint256 collateralToSeize = (collateralValueSeizedInBorrow * 1e18) / oraclePriceRatio;

        if (collateralToSeize > acc.collateralBalance) {
            collateralToSeize = acc.collateralBalance;
        }

        acc.collateralBalance -= collateralToSeize;
        totalCollateral -= collateralToSeize;
        collateralToken.transfer(msg.sender, collateralToSeize);

        emit Liquidated(borrower, msg.sender, repayAmount, collateralToSeize);
    }
}

// -----------------------------------------------------------------------------
// NFT Marketplace & Generative Asset Engine
// -----------------------------------------------------------------------------
contract MagnumNFTCollection is ReentrancyGuard, Ownable {
    string public name = "Magnum Opus Nexus NFT";
    string public symbol = "MONFT";
    uint256 public nextTokenId = 1;
    uint256 public maxSupply = 10000;
    uint256 public mintPrice = 0.05 ether;
    uint96 public royaltyBps = 500; // 5% Royalty

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint256 => string) private _tokenURIs;

    struct Listing {
        uint256 price;
        address seller;
        bool active;
    }
    mapping(uint256 => Listing) public listings;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed spender, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event NFTMinted(address indexed recipient, uint256 indexed tokenId, string tokenURI);
    event NFTListed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event NFTSold(uint256 indexed tokenId, address indexed buyer, address indexed seller, uint256 price);
    event ListingCancelled(uint256 indexed tokenId, address indexed seller);

    constructor() Ownable(msg.sender) {}

    function balanceOf(address ownerAddress) external view returns (uint256) {
        if (ownerAddress == address(0)) revert ZeroAddress();
        return _balances[ownerAddress];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address ownerAddress = _owners[tokenId];
        if (ownerAddress == address(0)) revert TokenDoesNotExist();
        return ownerAddress;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();
        return _tokenURIs[tokenId];
    }

    function approve(address to, uint256 tokenId) external {
        address ownerAddress = ownerOf(tokenId);
        if (msg.sender != ownerAddress && !_operatorApprovals[ownerAddress][msg.sender]) revert Unauthorized();
        _tokenApprovals[tokenId] = to;
        emit Approval(ownerAddress, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (ownerOf(tokenId) != from) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();
        if (msg.sender != from && _tokenApprovals[tokenId] != msg.sender && !_operatorApprovals[from][msg.sender]) {
            revert Unauthorized();
        }

        delete _tokenApprovals[tokenId];
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function mintNFT(string calldata _uri) external payable nonReentrant returns (uint256) {
        if (nextTokenId > maxSupply) revert MaxSupplyReached();
        if (msg.value < mintPrice) revert InsufficientBalance(msg.value, mintPrice);

        uint256 tokenId = nextTokenId++;
        _owners[tokenId] = msg.sender;
        _balances[msg.sender] += 1;
        _tokenURIs[tokenId] = _uri;

        emit Transfer(address(0), msg.sender, tokenId);
        emit NFTMinted(msg.sender, tokenId, _uri);
        return tokenId;
    }

    function listNFT(uint256 tokenId, uint256 price) external {
        if (ownerOf(tokenId) != msg.sender) revert Unauthorized();
        if (price == 0) revert ZeroAmount();

        listings[tokenId] = Listing(price, msg.sender, true);
        emit NFTListed(tokenId, msg.sender, price);
    }

    function buyNFT(uint256 tokenId) external payable nonReentrant {
        Listing memory item = listings[tokenId];
        if (!item.active) revert Unauthorized();
        if (msg.value < item.price) revert InsufficientBalance(msg.value, item.price);

        listings[tokenId].active = false;
        address seller = item.seller;

        uint256 royalty = (item.price * royaltyBps) / 10000;
        uint256 sellerProceeds = item.price - royalty;

        transferFrom(seller, msg.sender, tokenId);

        payable(owner()).transfer(royalty);
        payable(seller).transfer(sellerProceeds);

        emit NFTSold(tokenId, msg.sender, seller, item.price);
    }

    function cancelListing(uint256 tokenId) external {
        Listing memory item = listings[tokenId];
        if (item.seller != msg.sender) revert Unauthorized();
        delete listings[tokenId];
        emit ListingCancelled(tokenId, msg.sender);
    }

    function withdrawFees() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}

// -----------------------------------------------------------------------------
// Main Orchestration Governance Contract
// -----------------------------------------------------------------------------
contract MagnumNexusProtocol is Ownable, ReentrancyGuard {
    MagnumToken public immutable magnumToken;
    MagnumStakingVault public immutable stakingVault;
    MagnumLendingPool public immutable lendingPool;
    MagnumNFTCollection public immutable nftCollection;

    event ProtocolInitialized(address token, address staking, address lending, address nft);

    constructor(
        address _magnumToken,
        address _stakingVault,
        address _lendingPool,
        address _nftCollection
    ) Ownable(msg.sender) {
        magnumToken = MagnumToken(_magnumToken);
        stakingVault = MagnumStakingVault(_stakingVault);
        lendingPool = MagnumLendingPool(_lendingPool);
        nftCollection = MagnumNFTCollection(_nftCollection);
        emit ProtocolInitialized(_magnumToken, _stakingVault, _lendingPool, _nftCollection);
    }

    function getProtocolSummary() external view returns (
        uint256 totalTokenSupply,
        uint256 totalStaked,
        uint256 totalBorrowed,
        uint256 nftSupply
    ) {
        return (
            magnumToken.totalSupply(),
            stakingVault.totalStakedWeighted(),
            lendingPool.totalBorrows(),
            nftCollection.nextTokenId() - 1
        );
    }
}
