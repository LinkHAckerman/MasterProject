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
error TransferFailed();
error ArrayLengthMismatch();

// -----------------------------------------------------------------------------
// Common Math Library
// -----------------------------------------------------------------------------
library MagnumMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant PERCENT_BPS = 10000; // basis points = 0.01%

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

    function wmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y + (WAD / 2)) / WAD;
    }

    function wdiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * WAD + (y / 2)) / y;
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
// ERC20 Interface (minimal)
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

// -----------------------------------------------------------------------------
// MAGNUM ERC20 Token
// -----------------------------------------------------------------------------
contract MagnumToken is IERC20, Ownable, ReentrancyGuard, Pausable {
    string private _name = "Magnum Token";
    string private _symbol = "MAG";
    uint8 private constant _decimals = 18;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);

    constructor(address initialOwner) Ownable(initialOwner) {}

    // -----------------------------------------------------
    // ERC20 standard view functions
    // -----------------------------------------------------
    function name() public view returns (string memory) { return _name; }
    function symbol() public view returns (string memory) { return _symbol; }
    function decimals() public pure returns (uint8) { return _decimals; }
    function totalSupply() public view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address owner, address spender) public view override returns (uint256) { return _allowances[owner][spender]; }

    // -----------------------------------------------------
    // ERC20 core logic
    // -----------------------------------------------------
    function transfer(address recipient, uint256 amount) public override whenNotPaused nonReentrant returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public override whenNotPaused returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override whenNotPaused nonReentrant returns (bool) {
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        if (currentAllowance < amount) revert InsufficientAllowance(currentAllowance, amount);
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), currentAllowance - amount);
        return true;
    }

    // -----------------------------------------------------
    // Mint / Burn – onlyOwner
    // -----------------------------------------------------
    function mint(address to, uint256 amount) external onlyOwner whenNotPaused {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        _totalSupply += amount;
        _balances[to] += amount;
        emit Mint(to, amount);
        emit Transfer(address(0), to, amount);
    }

    function burn(uint256 amount) external whenNotPaused {
        address account = _msgSender();
        uint256 balance = _balances[account];
        if (balance < amount) revert InsufficientBalance(balance, amount);
        _balances[account] = balance - amount;
        _totalSupply -= amount;
        emit Burn(account, amount);
        emit Transfer(account, address(0), amount);
    }

    // -----------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------
    function _transfer(address sender, address recipient, uint256 amount) internal {
        if (sender == address(0) || recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 senderBal = _balances[sender];
        if (senderBal < amount) revert InsufficientBalance(senderBal, amount);
        _balances[sender] = senderBal - amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    function _approve(address ownerAddr, address spender, uint256 amount) internal {
        if (ownerAddr == address(0) || spender == address(0)) revert ZeroAddress();
        _allowances[ownerAddr][spender] = amount;
        emit Approval(ownerAddr, spender, amount);
    }

    // -----------------------------------------------------
    // Pausable controls – onlyOwner
    // -----------------------------------------------------
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}

// -----------------------------------------------------------------------------
// ERC721 Minimal Implementation
// -----------------------------------------------------------------------------
contract MagnumNFT is Ownable, Pausable {
    string private _name = "Magnum NFT";
    string private _symbol = "MAGNFT";
    uint256 private _currentTokenId;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event Mint(address indexed to, uint256 indexed tokenId);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function name() public view returns (string memory) { return _name; }
    function symbol() public view returns (string memory) { return _symbol; }
    function balanceOf(address ownerAddr) public view returns (uint256) {
        if (ownerAddr == address(0)) revert ZeroAddress();
        return _balances[ownerAddr];
    }
    function ownerOf(uint256 tokenId) public view returns (address) {
        address ownerAddr = _owners[tokenId];
        if (ownerAddr == address(0)) revert TokenDoesNotExist();
        return ownerAddr;
    }

    function approve(address to, uint256 tokenId) public whenNotPaused {
        address ownerAddr = ownerOf(tokenId);
        if (to == ownerAddr) revert InvalidRoyaltyPercentage(); // reuse error for brevity
        if (_msgSender() != ownerAddr && !isApprovedForAll(ownerAddr, _msgSender())) revert Unauthorized();
        _tokenApprovals[tokenId] = to;
        emit Approval(ownerAddr, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public whenNotPaused {
        if (operator == _msgSender()) revert IdenticalAddresses();
        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    function isApprovedForAll(address ownerAddr, address operator) public view returns (bool) {
        return _operatorApprovals[ownerAddr][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public whenNotPaused {
        if (!_isApprovedOrOwner(_msgSender(), tokenId)) revert Unauthorized();
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public whenNotPaused {
        transferFrom(from, to, tokenId);
        // Note: ERC721Receiver check omitted for brevity
    }

    function mint(address to) external onlyOwner whenNotPaused returns (uint256) {
        if (to == address(0)) revert ZeroAddress();
        _currentTokenId++;
        uint256 newTokenId = _currentTokenId;
        _owners[newTokenId] = to;
        _balances[to] += 1;
        emit Mint(to, newTokenId);
        emit Transfer(address(0), to, newTokenId);
        return newTokenId;
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        if (ownerOf(tokenId) != from) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();
        // clear approvals
        delete _tokenApprovals[tokenId];
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address ownerAddr = ownerOf(tokenId);
        return (spender == ownerAddr || getApproved(tokenId) == spender || isApprovedForAll(ownerAddr, spender));
    }

    // Pausable controls – onlyOwner
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}

// -----------------------------------------------------------------------------
// Simple Constant-Product AMM Swap (ERC20 <-> ERC20)
// -----------------------------------------------------------------------------
contract SimpleSwap is Ownable, ReentrancyGuard, Pausable {
    IERC20 public tokenA;
    IERC20 public tokenB;
    uint256 public reserveA;
    uint256 public reserveB;
    uint256 public constant FEE_BPS = 30; // 0.30% fee

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB);
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB);
    event Swapped(address indexed trader, address indexed tokenIn, uint256 amountIn, address indexed tokenOut, uint256 amountOut);

    constructor(address _owner, address _tokenA, address _tokenB) Ownable(_owner) {
        if (_tokenA == address(0) || _tokenB == address(0)) revert ZeroAddress();
        if (_tokenA == _tokenB) revert IdenticalAddresses();
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    // -----------------------------------------------------
    // Add liquidity – provider must approve tokens beforehand
    // -----------------------------------------------------
    function addLiquidity(uint256 amountA, uint256 amountB) external whenNotPaused nonReentrant {
        if (amountA == 0 || amountB == 0) revert ZeroAmount();
        // Transfer tokens from provider
        tokenA.transferFrom(_msgSender(), address(this), amountA);
        tokenB.transferFrom(_msgSender(), address(this), amountB);
        reserveA += amountA;
        reserveB += amountB;
        emit LiquidityAdded(_msgSender(), amountA, amountB);
    }

    // -----------------------------------------------------
    // Remove liquidity – simple proportional withdrawal
    // -----------------------------------------------------
    function removeLiquidity(uint256 sharePercentBps) external whenNotPaused nonReentrant {
        if (sharePercentBps == 0 || sharePercentBps > MagnumMath.PERCENT_BPS) revert InvalidRoyaltyPercentage();
        uint256 amountA = MagnumMath.wmul(reserveA, sharePercentBps) / MagnumMath.PERCENT_BPS;
        uint256 amountB = MagnumMath.wmul(reserveB, sharePercentBps) / MagnumMath.PERCENT_BPS;
        if (amountA == 0 && amountB == 0) revert ZeroAmount();
        reserveA -= amountA;
        reserveB -= amountB;
        tokenA.transfer(_msgSender(), amountA);
        tokenB.transfer(_msgSender(), amountB);
        emit LiquidityRemoved(_msgSender(), amountA, amountB);
    }

    // -----------------------------------------------------
    // Swap – constant product formula with fee
    // -----------------------------------------------------
    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut) external whenNotPaused nonReentrant returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();
        bool isAtoB = tokenIn == address(tokenA);
        if (!isAtoB && tokenIn != address(tokenB)) revert IdenticalAddresses();
        IERC20 inToken = isAtoB ? tokenA : tokenB;
        IERC20 outToken = isAtoB ? tokenB : tokenA;
        uint256 reserveIn = isAtoB ? reserveA : reserveB;
        uint256 reserveOut = isAtoB ? reserveB : reserveA;
        // Transfer in
        inToken.transferFrom(_msgSender(), address(this), amountIn);
        // Apply fee
        uint256 amountInWithFee = amountIn - MagnumMath.wmul(amountIn, FEE_BPS) / MagnumMath.PERCENT_BPS;
        // Constant product: x*y = k => dy = y - k/(x+dx)
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn + amountInWithFee;
        amountOut = numerator / denominator;
        if (amountOut < minAmountOut) revert InsufficientOutputAmount(amountOut, minAmountOut);
        // Update reserves
        if (isAtoB) {
            reserveA += amountIn;
            reserveB -= amountOut;
        } else {
            reserveB += amountIn;
            reserveA -= amountOut;
        }
        // Transfer out
        outToken.transfer(_msgSender(), amountOut);
        emit Swapped(_msgSender(), tokenIn, amountIn, address(outToken), amountOut);
    }

    // -----------------------------------------------------
    // View helpers
    // -----------------------------------------------------
    function getReserves() external view returns (uint256 _reserveA, uint256 _reserveB) {
        return (reserveA, reserveB);
    }

    // Pausable controls – onlyOwner
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}
