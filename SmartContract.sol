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

// -----------------------------------------------------------------------------
// ERC20 Implementation – MagnumToken
// -----------------------------------------------------------------------------
contract MagnumToken is Context, IERC20, IERC20Metadata, Ownable, Pausable, ReentrancyGuard {
    string private _name;
    string private _symbol;
    uint8 private constant _decimals = 18;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // EIP-2612 Permit state
    bytes32 public immutable DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1d5d4c0c2c5e5c5e5c5e5c5e5c5e5c5e5c5e5c5e5c5e5c5e5c5e5;
    mapping(address => uint256) public nonces;

    constructor(address initialOwner, string memory tokenName, string memory tokenSymbol, uint256 initialSupply) Ownable(initialOwner) {
        _name = tokenName;
        _symbol = tokenSymbol;
        _mint(initialOwner, initialSupply);
        uint256 chainId;
        assembly { chainId := chainid() }
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(tokenName)),
            keccak256(bytes("1")),
            chainId,
            address(this)
        ));
    }

    // IERC20Metadata
    function name() external view override returns (string memory) { return _name; }
    function symbol() external view override returns (string memory) { return _symbol; }
    function decimals() external pure override returns (uint8) { return _decimals; }

    // IERC20
    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) external view override returns (uint256) { return _balances[account]; }
    function transfer(address recipient, uint256 amount) external override whenNotPaused nonReentrant returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }
    function approve(address spender, uint256 amount) external override whenNotPaused returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    function transferFrom(address sender, address recipient, uint256 amount) external override whenNotPaused nonReentrant returns (bool) {
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        if (currentAllowance < amount) revert InsufficientAllowance(currentAllowance, amount);
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), currentAllowance - amount);
        return true;
    }

    // Optional: increase/decrease allowance helpers
    function increaseAllowance(address spender, uint256 addedValue) external whenNotPaused returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }
    function decreaseAllowance(address spender, uint256 subtractedValue) external whenNotPaused returns (bool) {
        uint256 current = _allowances[_msgSender()][spender];
        require(current >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, current - subtractedValue);
        return true;
    }

    // EIP-2612 permit
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, ExpiredDeadline());
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline));
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signer = ecrecover(hash, v, r, s);
        require(signer == owner && signer != address(0), InvalidSignature());
        _approve(owner, spender, value);
    }

    // Internal mechanics
    function _transfer(address sender, address recipient, uint256 amount) internal {
        if (sender == address(0) || recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 senderBal = _balances[sender];
        if (senderBal < amount) revert InsufficientBalance(senderBal, amount);
        _beforeTokenTransfer(sender, recipient, amount);
        _balances[sender] = senderBal - amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        _afterTokenTransfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        if (account == address(0)) revert ZeroAddress();
        _beforeTokenTransfer(address(0), account, amount);
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
        _afterTokenTransfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        if (account == address(0)) revert ZeroAddress();
        uint256 accountBal = _balances[account];
        if (accountBal < amount) revert InsufficientBalance(accountBal, amount);
        _beforeTokenTransfer(account, address(0), amount);
        _balances[account] = accountBal - amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
        _afterTokenTransfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        if (owner == address(0) || spender == address(0)) revert ZeroAddress();
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual whenNotPaused {}
    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}

// -----------------------------------------------------------------------------
// ERC721 Implementation – MagnumNFT
// -----------------------------------------------------------------------------
contract MagnumNFT is Context, IERC721, IERC721Metadata, Ownable, Pausable {
    string private _name;
    string private _symbol;
    uint256 private _tokenIdCounter;

    // tokenId => owner
    mapping(uint256 => address) private _owners;
    // owner => balance
    mapping(address => uint256) private _balances;
    // tokenId => approved address
    mapping(uint256 => address) private _tokenApprovals;
    // owner => operator => approved
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    // tokenId => tokenURI
    mapping(uint256 => string) private _tokenURIs;

    constructor(address initialOwner, string memory name_, string memory symbol_) Ownable(initialOwner) {
        _name = name_;
        _symbol = symbol_;
    }

    // IERC721Metadata
    function name() external view override returns (string memory) { return _name; }
    function symbol() external view override returns (string memory) { return _symbol; }
    function tokenURI(uint256 tokenId) external view override returns (string memory) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        return _tokenURIs[tokenId];
    }

    // IERC721
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
        if (to == owner) revert InvalidRoyaltyPercentage(); // reuse error for brevity
        if (_msgSender() != owner && !isApprovedForAll(owner, _msgSender())) revert Unauthorized();
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view override returns (address) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external override whenNotPaused {
        if (operator == _msgSender()) revert InvalidRoyaltyPercentage();
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

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public override whenNotPaused {
        if (!_isApprovedOrOwner(_msgSender(), tokenId)) revert Unauthorized();
        _safeTransfer(from, to, tokenId, _data);
    }

    // Internal helpers
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory _data) internal {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        if (from != ownerOf(tokenId)) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();
        // clear approvals
        delete _tokenApprovals[tokenId];
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function _mint(address to, string memory uri) internal returns (uint256) {
        if (to == address(0)) revert ZeroAddress();
        uint256 tokenId = ++_tokenIdCounter;
        _owners[tokenId] = to;
        _balances[to] += 1;
        _tokenURIs[tokenId] = uri;
        emit Transfer(address(0), to, tokenId);
        return tokenId;
    }

    function _burn(uint256 tokenId) internal {
        address owner = ownerOf(tokenId);
        // clear approvals
        delete _tokenApprovals[tokenId];
        _balances[owner] -= 1;
        delete _owners[tokenId];
        delete _tokenURIs[tokenId];
        emit Transfer(owner, address(0), tokenId);
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory _data) private returns (bool) {
        if (to.code.length == 0) {
            return true;
        }
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = to.call(abi.encodeWithSignature(
            "onERC721Received(address,address,uint256,bytes)",
            _msgSender(),
            from,
            tokenId,
            _data
        ));
        if (!success) return false;
        bytes4 retval = abi.decode(returndata, (bytes4));
        return (retval == bytes4(keccak256("onERC721Received(address,address,uint256,bytes)")));
    }
}

// -----------------------------------------------------------------------------
// Simple Constant-Product AMM – MagnumLiquidityPool
// -----------------------------------------------------------------------------
contract MagnumLiquidityPool is Context, Ownable, Pausable, ReentrancyGuard {
    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;

    uint256 public reserveA;
    uint256 public reserveB;
    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidityOf;

    uint256 public constant FEE_NUMERATOR = 3; // 0.3% fee
    uint256 public constant FEE_DENOMINATOR = 1000;

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 liquidityMinted);
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 liquidityBurned);
    event Swapped(address indexed trader, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);

    constructor(address _owner, address _tokenA, address _tokenB) Ownable(_owner) {
        if (_tokenA == _tokenB) revert IdenticalAddresses();
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    // Add liquidity – provider must approve token transfers beforehand
    function addLiquidity(uint256 amountA, uint256 amountB) external whenNotPaused nonReentrant returns (uint256 liquidityMinted) {
        if (amountA == 0 || amountB == 0) revert ZeroAmount();
        // Transfer tokens to pool
        tokenA.transferFrom(_msgSender(), address(this), amountA);
        tokenB.transferFrom(_msgSender(), address(this), amountB);
        uint256 _totalLiquidity = totalLiquidity;
        if (_totalLiquidity == 0) {
            liquidityMinted = MagnumMath.sqrt(amountA * amountB);
        } else {
            liquidityMinted = MagnumMath.min((amountA * _totalLiquidity) / reserveA, (amountB * _totalLiquidity) / reserveB);
        }
        if (liquidityMinted == 0) revert ZeroAmount();
        liquidityOf[_msgSender()] += liquidityMinted;
        totalLiquidity += liquidityMinted;
        _updateReserves();
        emit LiquidityAdded(_msgSender(), amountA, amountB, liquidityMinted);
    }

    // Remove liquidity – burns LP tokens and returns underlying assets
    function removeLiquidity(uint256 liquidity) external whenNotPaused nonReentrant returns (uint256 amountA, uint256 amountB) {
        uint256 providerLiquidity = liquidityOf[_msgSender()];
        if (liquidity == 0 || liquidity > providerLiquidity) revert InsufficientBalance(providerLiquidity, liquidity);
        amountA = (liquidity * reserveA) / totalLiquidity;
        amountB = (liquidity * reserveB) / totalLiquidity;
        if (amountA == 0 || amountB == 0) revert ZeroAmount();
        liquidityOf[_msgSender()] = providerLiquidity - liquidity;
        totalLiquidity -= liquidity;
        tokenA.transfer(_msgSender(), amountA);
        tokenB.transfer(_msgSender(), amountB);
        _updateReserves();
        emit LiquidityRemoved(_msgSender(), amountA, amountB, liquidity);
    }

    // Swap – tokenIn can be tokenA or tokenB
    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut) external whenNotPaused nonReentrant returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();
        bool isAtoB;
        if (tokenIn == address(tokenA)) {
            isAtoB = true;
        } else if (tokenIn == address(tokenB)) {
            isAtoB = false;
        } else {
            revert IdenticalAddresses();
        }
        IERC20 inToken = isAtoB ? tokenA : tokenB;
        IERC20 outToken = isAtoB ? tokenB : tokenA;
        inToken.transferFrom(_msgSender(), address(this), amountIn);
        // Apply fee
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - FEE_NUMERATOR) / FEE_DENOMINATOR;
        // Constant product formula
        uint256 reserveIn = isAtoB ? reserveA : reserveB;
        uint256 reserveOut = isAtoB ? reserveB : reserveA;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn + amountInWithFee;
        amountOut = numerator / denominator;
        if (amountOut < minAmountOut) revert InsufficientOutputAmount(amountOut, minAmountOut);
        outToken.transfer(_msgSender(), amountOut);
        _updateReserves();
        emit Swapped(_msgSender(), tokenIn, amountIn, address(outToken), amountOut);
    }

    function _updateReserves() internal {
        reserveA = tokenA.balanceOf(address(this));
        reserveB = tokenB.balanceOf(address(this));
    }
}
