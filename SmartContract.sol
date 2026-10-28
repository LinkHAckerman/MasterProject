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
// Core ERC20 Implementation – Magnum Token
// -----------------------------------------------------------------------------
contract MagnumToken is Context, Ownable, Pausable, ReentrancyGuard, IERC20, IERC20Metadata {
    string private _name = "Magnum Token";
    string private _symbol = "MAG";
    uint8 private constant _decimals = 18;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(address initialOwner, uint256 initialSupply) Ownable(initialOwner) {
        _mint(initialOwner, initialSupply);
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
        if (currentAllowance < amount) revert InsufficientAllowance({available: currentAllowance, required: amount});
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), currentAllowance - amount);
        return true;
    }

    // Internal helpers
    function _transfer(address sender, address recipient, uint256 amount) internal {
        if (sender == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();
        uint256 senderBal = _balances[sender];
        if (senderBal < amount) revert InsufficientBalance({available: senderBal, required: amount});
        unchecked {
            _balances[sender] = senderBal - amount;
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

    function mint(address to, uint256 amount) external onlyOwner whenNotPaused {
        _mint(to, amount);
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

    function burn(uint256 amount) external whenNotPaused {
        _burn(_msgSender(), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        if (owner == address(0) || spender == address(0)) revert ZeroAddress();
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // Administrative controls
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

// -----------------------------------------------------------------------------
// Simple ERC721 Implementation – Magnum NFT
// -----------------------------------------------------------------------------
contract MagnumNFT is Context, Ownable, Pausable, ReentrancyGuard, IERC721Metadata {
    string private _name = "Magnum NFT";
    string private _symbol = "MAGNFT";
    uint256 private _tokenIdCounter;
    string private _baseTokenURI;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    constructor(address initialOwner, string memory baseURI) Ownable(initialOwner) {
        _baseTokenURI = baseURI;
    }

    // IERC721Metadata
    function name() external view override returns (string memory) { return _name; }
    function symbol() external view override returns (string memory) { return _symbol; }
    function tokenURI(uint256 tokenId) external view override returns (string memory) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        return string(abi.encodePacked(_baseTokenURI, _toString(tokenId)));
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

    function approve(address to, uint256 tokenId) external override whenNotPaused nonReentrant {
        address owner = ownerOf(tokenId);
        if (to == owner) revert Unauthorized();
        if (_msgSender() != owner && !isApprovedForAll(owner, _msgSender())) revert Unauthorized();
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view override returns (address) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external override whenNotPaused {
        if (operator == _msgSender()) revert Unauthorized();
        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public override whenNotPaused nonReentrant {
        if (!_isApprovedOrOwner(_msgSender(), tokenId)) revert Unauthorized();
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public override whenNotPaused nonReentrant {
        if (!_isApprovedOrOwner(_msgSender(), tokenId)) revert Unauthorized();
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    // Internal functions
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    function _safeMint(address to) internal {
        _mint(to);
        require(_checkOnERC721Received(address(0), to, _tokenIdCounter, ""), "ERC721: transfer to non ERC721Receiver implementer");
    }

    function mint(address to) external onlyOwner whenNotPaused nonReentrant {
        _mint(to);
    }

    function _mint(address to) internal {
        if (to == address(0)) revert ZeroAddress();
        _tokenIdCounter += 1;
        uint256 tokenId = _tokenIdCounter;
        _owners[tokenId] = to;
        _balances[to] += 1;
        emit Transfer(address(0), to, tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        if (ownerOf(tokenId) != from) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();
        // Clear approvals
        delete _tokenApprovals[tokenId];
        // Update balances
        _balances[from] -= 1;
        _balances[to] += 1;
        // Transfer ownership
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory _data) private returns (bool) {
        if (to.code.length == 0) {
            return true;
        }
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = to.call(abi.encodeWithSelector(
            bytes4(keccak256("onERC721Received(address,address,uint256,bytes)")),
            _msgSender(), from, tokenId, _data
        ));
        if (!success) return false;
        bytes4 retval = abi.decode(returndata, (bytes4));
        return retval == bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }

    // Utility to convert uint256 to string
    function _toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // Administrative controls
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
