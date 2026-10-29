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

interface IERC721 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function setApprovalForAll(address operator, bool _approved) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

interface IERC721Metadata is IERC721 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

interface IUniswapV2Router02 {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

// -----------------------------------------------------------------------------
// ERC20 Implementation – Magnum Token
// -----------------------------------------------------------------------------
contract MagnumToken is IERC20Metadata, Ownable, Pausable, ReentrancyGuard {
    string private _name = "Magnum Token";
    string private _symbol = "MAG";
    uint8 private constant _decimals = 18;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(address initialOwner, uint256 initialSupply) Ownable(initialOwner) {
        _mint(initialOwner, initialSupply);
    }

    // ---------- IERC20Metadata ----------
    function name() external view override returns (string memory) { return _name; }
    function symbol() external view override returns (string memory) { return _symbol; }
    function decimals() external pure override returns (uint8) { return _decimals; }

    // ---------- IERC20 ----------
    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) external view override returns (uint256) { return _balances[account]; }
    function allowance(address owner, address spender) external view override returns (uint256) { return _allowances[owner][spender]; }

    function transfer(address recipient, uint256 amount) external override whenNotPaused nonReentrant returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override whenNotPaused returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override whenNotPaused nonReentrant returns (bool) {
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        if (currentAllowance < amount) revert InsufficientAllowance({available: currentAllowance, required: amount});
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), currentAllowance - amount);
        return true;
    }

    // ---------- Internal Helpers ----------
    function _transfer(address sender, address recipient, uint256 amount) internal {
        if (sender == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 senderBal = _balances[sender];
        if (senderBal < amount) revert InsufficientBalance({available: senderBal, required: amount});
        unchecked {
            _balances[sender] = senderBal - amount;
            _balances[recipient] += amount;
        }
        emit Transfer(sender, recipient, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        if (owner == address(0) || spender == address(0)) revert ZeroAddress();
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // ---------- Mint / Burn (Owner only) ----------
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(_msgSender(), amount);
    }

    function _mint(address account, uint256 amount) internal {
        if (account == address(0)) revert ZeroAddress();
        unchecked { _totalSupply += amount; }
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        if (account == address(0)) revert ZeroAddress();
        uint256 accountBal = _balances[account];
        if (accountBal < amount) revert InsufficientBalance({available: accountBal, required: amount});
        unchecked {
            _balances[account] = accountBal - amount;
            _totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
    }

    // ---------- Pausable Controls (Owner) ----------
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

// -----------------------------------------------------------------------------
// ERC721 Implementation – Magnum NFT Collection
// -----------------------------------------------------------------------------
contract MagnumNFT is IERC721Metadata, Ownable, Pausable {
    string private _name = "Magnum NFT";
    string private _symbol = "MAGNFT";
    uint256 private _nextTokenId = 1;
    uint256 public maxSupply = 10000;

    // tokenId => owner
    mapping(uint256 => address) private _owners;
    // owner => balance
    mapping(address => uint256) private _balances;
    // tokenId => approved address
    mapping(uint256 => address) private _tokenApprovals;
    // owner => operator => approved
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    // tokenId => tokenURI (simple storage)
    mapping(uint256 => string) private _tokenURIs;

    constructor(address initialOwner) Ownable(initialOwner) {}

    // ---------- IERC721Metadata ----------
    function name() external view override returns (string memory) { return _name; }
    function symbol() external view override returns (string memory) { return _symbol; }
    function tokenURI(uint256 tokenId) external view override returns (string memory) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();
        return _tokenURIs[tokenId];
    }

    // ---------- IERC721 ----------
    function balanceOf(address owner) external view override returns (uint256) {
        if (owner == address(0)) revert ZeroAddress();
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert TokenDoesNotExist();
        return owner;
    }

    function approve(address to, uint256 tokenId) external override whenNotPaused {
        address owner = ownerOf(tokenId);
        if (to == owner) revert InvalidRoyaltyPercentage(); // reuse error for simplicity
        if (_msgSender() != owner && !isApprovedForAll(owner, _msgSender())) revert Unauthorized();
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view override returns (address) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external override whenNotPaused {
        if (operator == _msgSender()) revert IdenticalAddresses();
        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public override whenNotPaused {
        if (!_isApprovedOrOwner(_msgSender(), tokenId)) revert Unauthorized();
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external override whenNotPaused {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) public override whenNotPaused {
        if (!_isApprovedOrOwner(_msgSender(), tokenId)) revert Unauthorized();
        _transfer(from, to, tokenId);
        // Note: ERC721Receiver check omitted for brevity – assumed EOA or compliant contract.
    }

    // ---------- Minting (Owner) ----------
    function mint(address to, string calldata uri) external onlyOwner whenNotPaused {
        if (to == address(0)) revert ZeroAddress();
        if (_nextTokenId > maxSupply) revert MaxSupplyReached();
        uint256 tokenId = _nextTokenId;
        _nextTokenId++;
        _owners[tokenId] = to;
        _balances[to] += 1;
        _tokenURIs[tokenId] = uri;
        emit Transfer(address(0), to, tokenId);
    }

    // ---------- Internal ----------
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        if (ownerOf(tokenId) != from) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();
        // clear approvals
        delete _tokenApprovals[tokenId];
        // update balances
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }
}

// -----------------------------------------------------------------------------
// Staking Contract – Users stake MAG token to earn rewards
// -----------------------------------------------------------------------------
contract MagnumStaking is Ownable, ReentrancyGuard, Pausable {
    MagnumToken public immutable rewardToken;
    uint256 public rewardRatePerBlock; // reward tokens per block per staked token
    uint256 public lastUpdateBlock;
    uint256 public rewardPerTokenStored;

    struct StakeInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    mapping(address => StakeInfo) public stakes;
    uint256 public totalStaked;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 newRate);

    constructor(address tokenAddress, uint256 initialRewardRate) Ownable(_msgSender()) {
        rewardToken = MagnumToken(tokenAddress);
        rewardRatePerBlock = initialRewardRate;
        lastUpdateBlock = block.number;
    }

    // ---------- View Functions ----------
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) return rewardPerTokenStored;
        uint256 blocks = block.number - lastUpdateBlock;
        return rewardPerTokenStored + (blocks * rewardRatePerBlock * 1e18) / totalStaked;
    }

    function earned(address account) public view returns (uint256) {
        StakeInfo memory info = stakes[account];
        uint256 accrued = (info.amount * (rewardPerToken() - info.rewardDebt)) / 1e18;
        return accrued;
    }

    // ---------- Mutative Functions ----------
    function updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateBlock = block.number;
        if (account != address(0)) {
            stakes[account].rewardDebt = rewardPerTokenStored;
        }
    }

    function stake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        updateReward(_msgSender());
        rewardToken.transferFrom(_msgSender(), address(this), amount);
        stakes[_msgSender()].amount += amount;
        totalStaked += amount;
        emit Staked(_msgSender(), amount);
    }

    function withdraw(uint256 amount) external nonReentrant whenNotPaused {
        StakeInfo storage info = stakes[_msgSender()];
        if (amount > info.amount) revert InsufficientBalance({available: info.amount, required: amount});
        updateReward(_msgSender());
        info.amount -= amount;
        totalStaked -= amount;
        rewardToken.transfer(_msgSender(), amount);
        emit Withdrawn(_msgSender(), amount);
    }

    function claimReward() external nonReentrant whenNotPaused {
        updateReward(_msgSender());
        uint256 reward = earned(_msgSender());
        if (reward > 0) {
            stakes[_msgSender()].rewardDebt = rewardPerTokenStored;
            rewardToken.transfer(_msgSender(), reward);
            emit RewardPaid(_msgSender(), reward);
        }
    }

    // ---------- Owner Controls ----------
    function setRewardRate(uint256 newRate) external onlyOwner {
        updateReward(address(0));
        rewardRatePerBlock = newRate;
        emit RewardRateUpdated(newRate);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

// -----------------------------------------------------------------------------
// Simple DEX Router – Swap MAG token with another ERC20 token
// -----------------------------------------------------------------------------
contract MagnumDEX is Ownable, ReentrancyGuard, Pausable {
    struct Pair {
        uint256 reserve0; // token0 reserve
        uint256 reserve1; // token1 reserve
        uint256 totalLiquidity;
    }

    // token0 => token1 => Pair
    mapping(address => mapping(address => Pair)) public pairs;
    uint256 public constant FEE_DENOMINATOR = 10_000; // 0.3% fee => 30 / 10_000
    uint256 public constant FEE_NUMERATOR = 30;

    event LiquidityAdded(address indexed provider, address token0, address token1, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed provider, address token0, address token1, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Swapped(address indexed trader, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "Identical token addresses");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (uint256 liquidity) {
        if (block.timestamp > deadline) revert ExpiredDeadline();
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        Pair storage pair = pairs[token0][token1];
        // Transfer tokens to contract
        IERC20(token0).transferFrom(_msgSender(), address(this), amountADesired);
        IERC20(token1).transferFrom(_msgSender(), address(this), amountBDesired);
        // Simple proportional liquidity minting
        uint256 amount0 = amountADesired;
        uint256 amount1 = amountBDesired;
        if (pair.totalLiquidity == 0) {
            liquidity = MagnumMath.sqrt(amount0 * amount1) - 1000; // lock minimum liquidity
            pair.totalLiquidity = 1000; // lock
        } else {
            uint256 liquidity0 = (amount0 * pair.totalLiquidity) / pair.reserve0;
            uint256 liquidity1 = (amount1 * pair.totalLiquidity) / pair.reserve1;
            liquidity = MagnumMath.min(liquidity0, liquidity1);
        }
        if (liquidity == 0) revert InsufficientLiquidity();
        // Update reserves
        pair.reserve0 += amount0;
        pair.reserve1 += amount1;
        pair.totalLiquidity += liquidity;
        emit LiquidityAdded(to, token0, token1, amount0, amount1, liquidity);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (uint256 amount0, uint256 amount1) {
        if (block.timestamp > deadline) revert ExpiredDeadline();
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        Pair storage pair = pairs[token0][token1];
        if (liquidity > pair.totalLiquidity) revert InsufficientLiquidity();
        amount0 = (liquidity * pair.reserve0) / pair.totalLiquidity;
        amount1 = (liquidity * pair.reserve1) / pair.totalLiquidity;
        if (amount0 < amountAMin || amount1 < amountBMin) revert SlippageExceeded();
        pair.reserve0 -= amount0;
        pair.reserve1 -= amount1;
        pair.totalLiquidity -= liquidity;
        IERC20(token0).transfer(to, amount0);
        IERC20(token1).transfer(to, amount1);
        emit LiquidityRemoved(to, token0, token1, amount0, amount1, liquidity);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant whenNotPaused {
        if (block.timestamp > deadline) revert ExpiredDeadline();
        require(path.length >= 2, "Path too short");
        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];
        IERC20(tokenIn).transferFrom(_msgSender(), address(this), amountIn);
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - FEE_NUMERATOR) / FEE_DENOMINATOR;
        // Simplified constant product formula for a single pair (no multi-hop routing)
        (address token0, address token1) = _sortTokens(tokenIn, tokenOut);
        Pair storage pair = pairs[token0][token1];
        (uint256 reserveIn, uint256 reserveOut) = tokenIn == token0 ? (pair.reserve0, pair.reserve1) : (pair.reserve1, pair.reserve0);
        uint256 amountOut = (amountInWithFee * reserveOut) / (reserveIn + amountInWithFee);
        if (amountOut < amountOutMin) revert InsufficientOutputAmount({actual: amountOut, minimum: amountOutMin});
        // Update reserves
        if (tokenIn == token0) {
            pair.reserve0 += amountIn;
            pair.reserve1 -= amountOut;
        } else {
            pair.reserve1 += amountIn;
            pair.reserve0 -= amountOut;
        }
        IERC20(tokenOut).transfer(to, amountOut);
        emit Swapped(_msgSender(), tokenIn, tokenOut, amountIn, amountOut);
    }
}
