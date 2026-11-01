// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MAGNUM OPUS // Web3, DeFi & NFT Decentralized Nexus Platform
 * @notice Multi-protocol decentralized suite containing ERC20 Token with governance/staking,
 *         ERC721 dynamic NFT collection with royalties, DeFi Yield Vault with Automated
 *         Market Maker (AMM) router, and Flash Loan Provider.
 * @author Magnum Opus Core Blockchain Architecture Team
 */

// ============================================================================
// INTERFACES & ABSTRACT CONTRACTS
// ============================================================================

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
    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
}

interface IERC2981 {
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount);
}

interface IFlashLoanReceiver {
    function executeOperation(address token, uint256 amount, uint256 fee, bytes calldata params) external returns (bool);
}

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

abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert OwnableInvalidOwner(address(0));
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        if (owner() != msg.sender) revert OwnableUnauthorizedAccount(msg.sender);
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

abstract contract Pausable is Ownable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    error EnforcedPause();
    error ExpectedPause();

    constructor() {
        _paused = false;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    modifier whenNotPaused() {
        if (paused()) revert EnforcedPause();
        _;
    }

    modifier whenPaused() {
        if (!paused()) revert ExpectedPause();
        _;
    }

    function pause() public onlyOwner whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() public onlyOwner whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

// ============================================================================
// CORE TOKEN: MAGNUM TOKEN (ERC20 + STAKING + FLASH LOANS)
// ============================================================================

contract MagnumToken is IERC20Metadata, ReentrancyGuard, Pausable {
    string private _name;
    string private _symbol;
    uint8 private constant _DECIMALS = 18;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Staking details
    struct StakeInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 startTime;
        uint256 lockPeriod;
    }

    mapping(address => StakeInfo) public stakes;
    uint256 public totalStaked;
    uint256 public rewardRatePerSecond = 1e15;
    uint256 public constant FLASH_LOAN_FEE_BPS = 9; // 0.09% fee

    // Events
    event Staked(address indexed user, uint256 amount, uint256 lockPeriod);
    event Unstaked(address indexed user, uint256 amount, uint256 reward);
    event ClaimedReward(address indexed user, uint256 reward);
    event FlashLoanExecuted(address indexed receiver, uint256 amount, uint256 fee);

    // Custom errors
    error InvalidAmount();
    error InsufficientBalance();
    error InsufficientAllowance();
    error LockPeriodNotExpired();
    error FlashLoanFailed();

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        address admin
    ) Ownable(admin) {
        _name = name_;
        _symbol = symbol_;
        _mint(admin, initialSupply * (10 ** uint256(_DECIMALS)));
    }

    function name() external view override returns (string memory) { return _name; }
    function symbol() external view override returns (string memory) { return _symbol; }
    function decimals() external pure override returns (uint8) { return _DECIMALS; }
    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) external view override returns (uint256) { return _balances[account]; }

    function transfer(address recipient, uint256 amount) external override whenNotPaused returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override whenNotPaused returns (bool) {
        uint256 currentAllowance = _allowances[sender][msg.sender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert InsufficientAllowance();
            unchecked {
                _approve(sender, msg.sender, currentAllowance - amount);
            }
        }
        _transfer(sender, recipient, amount);
        return true;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function stake(uint256 amount, uint256 lockPeriodSeconds) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();
        if (_balances[msg.sender] < amount) revert InsufficientBalance();

        StakeInfo storage userStake = stakes[msg.sender];
        if (userStake.amount > 0) {
            uint256 pending = _calculateReward(msg.sender);
            userStake.rewardDebt += pending;
        }

        _transfer(msg.sender, address(this), amount);

        userStake.amount += amount;
        userStake.startTime = block.timestamp;
        userStake.lockPeriod = lockPeriodSeconds;
        totalStaked += amount;

        emit Staked(msg.sender, amount, lockPeriodSeconds);
    }

    function unstake() external nonReentrant {
        StakeInfo storage userStake = stakes[msg.sender];
        if (userStake.amount == 0) revert InvalidAmount();
        if (block.timestamp < userStake.startTime + userStake.lockPeriod) revert LockPeriodNotExpired();

        uint256 reward = _calculateReward(msg.sender) + userStake.rewardDebt;
        uint256 amount = userStake.amount;

        userStake.amount = 0;
        userStake.rewardDebt = 0;
        totalStaked -= amount;

        _transfer(address(this), msg.sender, amount);
        if (reward > 0) {
            _mint(msg.sender, reward);
        }

        emit Unstaked(msg.sender, amount, reward);
    }

    function claimReward() external nonReentrant whenNotPaused {
        StakeInfo storage userStake = stakes[msg.sender];
        if (userStake.amount == 0) revert InvalidAmount();

        uint256 reward = _calculateReward(msg.sender) + userStake.rewardDebt;
        if (reward == 0) revert InvalidAmount();

        userStake.startTime = block.timestamp;
        userStake.rewardDebt = 0;

        _mint(msg.sender, reward);
        emit ClaimedReward(msg.sender, reward);
    }

    function flashLoan(IFlashLoanReceiver receiver, uint256 amount, bytes calldata params) external nonReentrant whenNotPaused returns (bool) {
        if (amount == 0) revert InvalidAmount();
        uint256 fee = (amount * FLASH_LOAN_FEE_BPS) / 10000;
        uint256 balanceBefore = _balances[address(this)];
        if (balanceBefore < amount) revert InsufficientBalance();

        _transfer(address(this), address(receiver), amount);

        if (!receiver.executeOperation(address(this), amount, fee, params)) {
            revert FlashLoanFailed();
        }

        uint256 balanceAfter = _balances[address(this)];
        if (balanceAfter < balanceBefore + fee) {
            revert FlashLoanFailed();
        }

        emit FlashLoanExecuted(address(receiver), amount, fee);
        return true;
    }

    function pendingReward(address account) external view returns (uint256) {
        return _calculateReward(account) + stakes[account].rewardDebt;
    }

    function _calculateReward(address account) internal view returns (uint256) {
        StakeInfo memory userStake = stakes[account];
        if (userStake.amount == 0) return 0;
        uint256 duration = block.timestamp - userStake.startTime;
        return (userStake.amount * duration * rewardRatePerSecond) / 1e18;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        if (sender == address(0) || recipient == address(0)) revert InvalidAmount();
        if (_balances[sender] < amount) revert InsufficientBalance();

        unchecked {
            _balances[sender] -= amount;
            _balances[recipient] += amount;
        }
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        if (account == address(0)) revert InvalidAmount();
        _totalSupply += amount;
        unchecked {
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        if (account == address(0)) revert InvalidAmount();
        if (_balances[account] < amount) revert InsufficientBalance();
        unchecked {
            _balances[account] -= amount;
            _totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        if (owner == address(0) || spender == address(0)) revert InvalidAmount();
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}

// ============================================================================
// NFT ENGINE: MAGNUM NFT COLLECTION (ERC721 + ERC2981 ROYALTIES)
// ============================================================================

contract MagnumNFT is IERC721, IERC2981, Ownable, Pausable {
    string private _name;
    string private _symbol;
    string private _baseTokenURI;

    uint256 private _tokenCounter;
    uint256 public immutable maxSupply;
    uint256 public mintPrice;

    address public royaltyReceiver;
    uint96 public royaltyBps = 500;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint256 => string) private _customURIs;

    event Minted(address indexed to, uint256 indexed tokenId, string uri);
    event RoyaltyUpdated(address indexed receiver, uint96 bps);

    error TokenDoesNotExist();
    error ExceedsMaxSupply();
    error InsufficientETH();
    error TransferToZeroAddress();
    error NotOwnerOrApproved();

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        uint256 maxSupply_,
        uint256 mintPrice_,
        address admin
    ) Ownable(admin) {
        _name = name_;
        _symbol = symbol_;
        _baseTokenURI = baseURI_;
        maxSupply = maxSupply_;
        mintPrice = mintPrice_;
        royaltyReceiver = admin;
    }

    function name() external view returns (string memory) { return _name; }
    function symbol() external view returns (string memory) { return _symbol; }

    function balanceOf(address owner) external view override returns (uint256) {
        if (owner == address(0)) revert TransferToZeroAddress();
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert TokenDoesNotExist();
        return owner;
    }

    function approve(address to, uint256 tokenId) external override whenNotPaused {
        address owner = ownerOf(tokenId);
        if (msg.sender != owner && !_operatorApprovals[owner][msg.sender]) {
            revert NotOwnerOrApproved();
        }
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) external view override returns (address) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external override {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) external view override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public override whenNotPaused {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotOwnerOrApproved();
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override whenNotPaused {
        transferFrom(from, to, tokenId);
    }

    function mint(address to, string calldata customURI) external payable whenNotPaused returns (uint256) {
        if (msg.value < mintPrice) revert InsufficientETH();
        if (_tokenCounter >= maxSupply) revert ExceedsMaxSupply();

        uint256 newId = ++_tokenCounter;
        _mint(to, newId);

        if (bytes(customURI).length > 0) {
            _customURIs[newId] = customURI;
        }

        emit Minted(to, newId, customURI);
        return newId;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();
        if (bytes(_customURIs[tokenId]).length > 0) {
            return _customURIs[tokenId];
        }
        return string(abi.encodePacked(_baseTokenURI, _uint2String(tokenId)));
    }

    function setRoyaltyInfo(address receiver, uint96 bps) external onlyOwner {
        royaltyReceiver = receiver;
        royaltyBps = bps;
        emit RoyaltyUpdated(receiver, bps);
    }

    function royaltyInfo(uint256, uint256 salePrice) external view override returns (address, uint256) {
        uint256 royaltyAmount = (salePrice * royaltyBps) / 10000;
        return (royaltyReceiver, royaltyAmount);
    }

    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || _tokenApprovals[tokenId] == spender || _operatorApprovals[owner][spender]);
    }

    function _mint(address to, uint256 tokenId) internal {
        if (to == address(0)) revert TransferToZeroAddress();
        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        if (ownerOf(tokenId) != from) revert NotOwnerOrApproved();
        if (to == address(0)) revert TransferToZeroAddress();

        _tokenApprovals[tokenId] = address(0);
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function _uint2String(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
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
}

// ============================================================================
// DEFI ENGINE: AUTOMATED MARKET MAKER & LIQUIDITY POOL VAULT
// ============================================================================

contract MagnumDeFiVault is ReentrancyGuard, Pausable {
    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;

    uint256 public reserveA;
    uint256 public reserveB;
    uint256 public totalLiquidity;

    mapping(address => uint256) public liquidityProviderShares;

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 shares);
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 shares);
    event Swapped(address indexed user, address indexed tokenIn, uint256 amountIn, uint256 amountOut);

    error InvalidTokens();
    error InsufficientLiquidity();
    error SlippageExceeded();

    constructor(address _tokenA, address _tokenB, address admin) Ownable(admin) {
        if (_tokenA == address(0) || _tokenB == address(0) || _tokenA == _tokenB) revert InvalidTokens();
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    function addLiquidity(uint256 amountADesired, uint256 amountBDesired) external nonReentrant whenNotPaused returns (uint256 shares) {
        tokenA.transferFrom(msg.sender, address(this), amountADesired);
        tokenB.transferFrom(msg.sender, address(this), amountBDesired);

        if (totalLiquidity == 0) {
            shares = _sqrt(amountADesired * amountBDesired);
        } else {
            uint256 shareA = (amountADesired * totalLiquidity) / reserveA;
            uint256 shareB = (amountBDesired * totalLiquidity) / reserveB;
            shares = shareA < shareB ? shareA : shareB;
        }

        if (shares == 0) revert InsufficientLiquidity();

        liquidityProviderShares[msg.sender] += shares;
        totalLiquidity += shares;

        _updateReserves();
        emit LiquidityAdded(msg.sender, amountADesired, amountBDesired, shares);
    }

    function removeLiquidity(uint256 shares) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        if (shares == 0 || liquidityProviderShares[msg.sender] < shares) revert InsufficientLiquidity();

        amountA = (shares * reserveA) / totalLiquidity;
        amountB = (shares * reserveB) / totalLiquidity;

        liquidityProviderShares[msg.sender] -= shares;
        totalLiquidity -= shares;

        tokenA.transfer(msg.sender, amountA);
        tokenB.transfer(msg.sender, amountB);

        _updateReserves();
        emit LiquidityRemoved(msg.sender, amountA, amountB, shares);
    }

    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut) external nonReentrant whenNotPaused returns (uint256 amountOut) {
        if (tokenIn != address(tokenA) && tokenIn != address(tokenB)) revert InvalidTokens();
        if (amountIn == 0) revert InsufficientLiquidity();

        bool isTokenA = tokenIn == address(tokenA);
        (IERC20 inputToken, IERC20 outputToken, uint256 resIn, uint256 resOut) = isTokenA
            ? (tokenA, tokenB, reserveA, reserveB)
            : (tokenB, tokenA, reserveB, reserveA);

        inputToken.transferFrom(msg.sender, address(this), amountIn);

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * resOut;
        uint256 denominator = (resIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;

        if (amountOut < minAmountOut) revert SlippageExceeded();

        outputToken.transfer(msg.sender, amountOut);
        _updateReserves();

        emit Swapped(msg.sender, tokenIn, amountIn, amountOut);
    }

    function getAmountOut(address tokenIn, uint256 amountIn) external view returns (uint256) {
        bool isTokenA = tokenIn == address(tokenA);
        (uint256 resIn, uint256 resOut) = isTokenA ? (reserveA, reserveB) : (reserveB, reserveA);
        if (resIn == 0 || resOut == 0) return 0;

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * resOut;
        uint256 denominator = (resIn * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    function _updateReserves() internal {
        reserveA = tokenA.balanceOf(address(this));
        reserveB = tokenB.balanceOf(address(this));
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
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
