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
    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool _approved) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

interface IFlashLoanReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

// -----------------------------------------------------------------------------
// MagnumToken: Core ERC20 Token with EIP-2612 Permit Capabilities
// -----------------------------------------------------------------------------
contract MagnumToken is Context, IERC20, IERC20Metadata, Ownable {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) public nonces;

    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private constant _DECIMALS = 18;

    bytes32 public DOMAIN_SEPARATOR;
    // bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71ed727dd870300fee744e88d3d50125039a341353a042cf3b2d402d5a8b0e;

    constructor(string memory name_, string memory symbol_, uint256 initialMint) Ownable(msg.sender) {
        _name = name_;
        _symbol = symbol_;
        if (initialMint > 0) {
            _mint(_msgSender(), initialMint);
        }

        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name_)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure override returns (uint8) {
        return _DECIMALS;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
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

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(_msgSender(), amount);
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp > deadline) revert SignatureExpired();

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address recoveredAddress = ecrecover(digest, v, r, s);

        if (recoveredAddress == address(0) || recoveredAddress != owner) revert InvalidSignature();
        _approve(owner, spender, value);
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

    function _approve(address owner, address spender, uint256 amount) internal {
        if (owner == address(0) || spender == address(0)) revert ZeroAddress();
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}

// -----------------------------------------------------------------------------
// MagnumNFT: Royalty-Compliant ERC721 Digital Asset Suite
// -----------------------------------------------------------------------------
contract MagnumNFT is Context, IERC721, Ownable {
    string private _name;
    string private _symbol;
    uint256 public constant MAX_SUPPLY = 10000;
    uint256 private _totalMinted;

    address public royaltyReceiver;
    uint96 public royaltyBps = 250; // 2.5%

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint256 => string) private _tokenURIs;

    constructor(string memory name_, string memory symbol_, address initialRoyaltyReceiver) Ownable(msg.sender) {
        _name = name_;
        _symbol = symbol_;
        royaltyReceiver = initialRoyaltyReceiver == address(0) ? msg.sender : initialRoyaltyReceiver;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function totalSupply() external view returns (uint256) {
        return _totalMinted;
    }

    function balanceOf(address owner) external view override returns (uint256) {
        if (owner == address(0)) revert ZeroAddress();
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert TokenDoesNotExist();
        return owner;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();
        return _tokenURIs[tokenId];
    }

    function mint(address to, string calldata uri) external onlyOwner returns (uint256) {
        if (_totalMinted >= MAX_SUPPLY) revert MaxSupplyReached();
        uint256 tokenId = ++_totalMinted;
        _owners[tokenId] = to;
        _balances[to] += 1;
        _tokenURIs[tokenId] = uri;

        emit Transfer(address(0), to, tokenId);
        return tokenId;
    }

    function setRoyaltyInfo(address receiver, uint96 bps) external onlyOwner {
        if (receiver == address(0)) revert ZeroAddress();
        if (bps > 10000) revert InvalidRoyaltyPercentage();
        royaltyReceiver = receiver;
        royaltyBps = bps;
    }

    function royaltyInfo(uint256, uint256 salePrice) external view returns (address, uint256) {
        uint256 royaltyAmount = (salePrice * royaltyBps) / 10000;
        return (royaltyReceiver, royaltyAmount);
    }

    function approve(address to, uint256 tokenId) external override {
        address owner = ownerOf(tokenId);
        if (to == owner) revert IdenticalAddresses();
        if (_msgSender() != owner && !isApprovedForAll(owner, _msgSender())) revert Unauthorized();

        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view override returns (address) {
        if (_owners[tokenId] == address(0)) revert TokenDoesNotExist();
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external override {
        if (operator == _msgSender()) revert IdenticalAddresses();
        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        if (!_isApprovedOrOwner(_msgSender(), tokenId)) revert Unauthorized();
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override {
        transferFrom(from, to, tokenId);
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, data) returns (bytes4 retval) {
                if (retval != IERC721Receiver.onERC721Received.selector) revert Unauthorized();
            } catch {
                revert Unauthorized();
            }
        }
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        if (ownerOf(tokenId) != from) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();

        delete _tokenApprovals[tokenId];
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }
}

// -----------------------------------------------------------------------------
// MagnumDEX: Constant-Product AMM Liquidity Pool & Flash Loan Provider
// -----------------------------------------------------------------------------
contract MagnumDEX is Context, ReentrancyGuard, Pausable, Ownable {
    using MagnumMath for uint256;

    IERC20 private immutable _token0;
    IERC20 private immutable _token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public totalLpSupply;
    mapping(address => uint256) public lpBalances;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to);
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor(address token0_, address token1_) Ownable(msg.sender) {
        if (token0_ == address(0) || token1_ == address(0)) revert ZeroAddress();
        if (token0_ == token1_) revert IdenticalAddresses();
        _token0 = IERC20(token0_);
        _token1 = IERC20(token1_);
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function addLiquidity(uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, address to) external nonReentrant whenNotPaused returns (uint256 amount0, uint256 amount1, uint256 liquidity) {
        (amount0, amount1) = _calculateOptimalLiquidity(amount0Desired, amount1Desired, amount0Min, amount1Min);
        
        _token0.transferFrom(_msgSender(), address(this), amount0);
        _token1.transferFrom(_msgSender(), address(this), amount1);

        liquidity = _mintLP(to, amount0, amount1);
    }

    function removeLiquidity(uint256 liquidity, uint256 amount0Min, uint256 amount1Min, address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (lpBalances[_msgSender()] < liquidity) revert InsufficientBalance(lpBalances[_msgSender()], liquidity);

        uint256 balance0 = _token0.balanceOf(address(this));
        uint256 balance1 = _token1.balanceOf(address(this));

        amount0 = (liquidity * balance0) / totalLpSupply;
        amount1 = (liquidity * balance1) / totalLpSupply;

        if (amount0 < amount0Min || amount1 < amount1Min) revert SlippageExceeded();

        lpBalances[_msgSender()] -= liquidity;
        totalLpSupply -= liquidity;

        _token0.transfer(to, amount0);
        _token1.transfer(to, amount1);

        _updateReserves(_token0.balanceOf(address(this)), _token1.balanceOf(address(this)));
        emit Burn(_msgSender(), amount0, amount1, to);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant whenNotPaused {
        if (amount0Out == 0 && amount1Out == 0) revert ZeroAmount();
        if (amount0Out > reserve0 || amount1Out > reserve1) revert InsufficientLiquidity();

        if (amount0Out > 0) _token0.transfer(to, amount0Out);
        if (amount1Out > 0) _token1.transfer(to, amount1Out);

        uint256 balance0 = _token0.balanceOf(address(this));
        uint256 balance1 = _token1.balanceOf(address(this));

        uint256 amount0In = balance0 > reserve0 - amount0Out ? balance0 - (reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > reserve1 - amount1Out ? balance1 - (reserve1 - amount1Out) : 0;

        if (amount0In == 0 && amount1In == 0) revert ZeroAmount();

        uint256 balance0Adjusted = balance0 * 1000 - (amount0In * 3);
        uint256 balance1Adjusted = balance1 * 1000 - (amount1In * 3);

        if (balance0Adjusted * balance1Adjusted < uint256(reserve0) * uint256(reserve1) * 1000000) {
            revert SlippageExceeded();
        }

        _updateReserves(balance0, balance1);
        emit Swap(_msgSender(), amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function flashLoan(address receiverAddress, address token, uint256 amount, bytes calldata data) external nonReentrant whenNotPaused {
        if (token != address(_token0) && token != address(_token1)) revert Unauthorized();
        if (amount == 0) revert ZeroAmount();

        IERC20 loanToken = IERC20(token);
        uint256 balanceBefore = loanToken.balanceOf(address(this));
        if (balanceBefore < amount) revert InsufficientLiquidity();

        uint256 fee = (amount * 9) / 10000; // 0.09% flash loan fee
        loanToken.transfer(receiverAddress, amount);

        bool success = IFlashLoanReceiver(receiverAddress).executeOperation(token, amount, fee, _msgSender(), data);
        if (!success) revert FlashLoanFailed();

        uint256 balanceAfter = loanToken.balanceOf(address(this));
        if (balanceAfter < balanceBefore + fee) revert FlashLoanFailed();

        _updateReserves(_token0.balanceOf(address(this)), _token1.balanceOf(address(this)));
    }

    function _calculateOptimalLiquidity(uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min) internal view returns (uint256 amount0, uint256 amount1) {
        if (reserve0 == 0 && reserve1 == 0) {
            (amount0, amount1) = (amount0Desired, amount1Desired);
        } else {
            uint256 amount1Optimal = (amount0Desired * reserve1) / reserve0;
            if (amount1Optimal <= amount1Desired) {
                if (amount1Optimal < amount1Min) revert SlippageExceeded();
                (amount0, amount1) = (amount0Desired, amount1Optimal);
            } else {
                uint256 amount0Optimal = (amount1Desired * reserve0) / reserve1;
                if (amount0Optimal < amount0Min) revert SlippageExceeded();
                (amount0, amount1) = (amount0Optimal, amount1Desired);
            }
        }
    }

    function _mintLP(address to, uint256 amount0, uint256 amount1) internal returns (uint256 liquidity) {
        if (totalLpSupply == 0) {
            liquidity = MagnumMath.sqrt(amount0 * amount1);
        } else {
            liquidity = MagnumMath.min((amount0 * totalLpSupply) / reserve0, (amount1 * totalLpSupply) / reserve1);
        }
        if (liquidity == 0) revert InsufficientLiquidity();

        totalLpSupply += liquidity;
        lpBalances[to] += liquidity;

        _updateReserves(_token0.balanceOf(address(this)), _token1.balanceOf(address(this)));
        emit Mint(to, amount0, amount1);
    }

    function _updateReserves(uint256 balance0, uint256 balance1) internal {
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp % 2**32);
        emit Sync(reserve0, reserve1);
    }
}

// -----------------------------------------------------------------------------
// MagnumStaking: Time-Locked Multi-Tier Yield Staking Suite
// -----------------------------------------------------------------------------
contract MagnumStaking is Context, ReentrancyGuard, Ownable, Pausable {
    IERC20 public immutable stakingToken;
    MagnumToken public immutable rewardToken;

    struct StakeInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lockPeriod;
        uint256 depositTimestamp;
    }

    uint256 public rewardPerSecond = 1e18; // 1 Reward token / second
    uint256 public lastRewardTime;
    uint256 public accRewardPerShare;
    uint256 public totalStaked;

    mapping(address => StakeInfo) public stakes;

    event Staked(address indexed user, uint256 amount, uint256 lockPeriod);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardHarvested(address indexed user, uint256 amount);

    constructor(address _stakingToken, address _rewardToken) Ownable(msg.sender) {
        if (_stakingToken == address(0) || _rewardToken == address(0)) revert ZeroAddress();
        stakingToken = IERC20(_stakingToken);
        rewardToken = MagnumToken(_rewardToken);
        lastRewardTime = block.timestamp;
    }

    function updatePool() public {
        if (block.timestamp <= lastRewardTime) return;
        if (totalStaked == 0) {
            lastRewardTime = block.timestamp;
            return;
        }
        uint256 timeElapsed = block.timestamp - lastRewardTime;
        uint256 rewardAmount = timeElapsed * rewardPerSecond;
        accRewardPerShare += (rewardAmount * 1e12) / totalStaked;
        lastRewardTime = block.timestamp;
    }

    function stake(uint256 amount, uint256 lockDays) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        updatePool();

        StakeInfo storage userStake = stakes[_msgSender()];
        if (userStake.amount > 0) {
            uint256 pending = (userStake.amount * accRewardPerShare) / 1e12 - userStake.rewardDebt;
            if (pending > 0) {
                _sendReward(_msgSender(), pending);
            }
        }

        stakingToken.transferFrom(_msgSender(), address(this), amount);
        userStake.amount += amount;
        userStake.depositTimestamp = block.timestamp;
        userStake.lockPeriod = lockDays * 1 days;
        userStake.rewardDebt = (userStake.amount * accRewardPerShare) / 1e12;

        totalStaked += amount;
        emit Staked(_msgSender(), amount, lockDays);
    }

    function withdraw(uint256 amount) external nonReentrant {
        StakeInfo storage userStake = stakes[_msgSender()];
        if (userStake.amount < amount) revert InsufficientBalance(userStake.amount, amount);
        if (block.timestamp < userStake.depositTimestamp + userStake.lockPeriod) {
            revert PositionLocked(userStake.depositTimestamp + userStake.lockPeriod);
        }

        updatePool();
        uint256 pending = (userStake.amount * accRewardPerShare) / 1e12 - userStake.rewardDebt;
        if (pending > 0) {
            _sendReward(_msgSender(), pending);
        }

        userStake.amount -= amount;
        userStake.rewardDebt = (userStake.amount * accRewardPerShare) / 1e12;
        totalStaked -= amount;

        stakingToken.transfer(_msgSender(), amount);
        emit Withdrawn(_msgSender(), amount);
    }

    function claimReward() external nonReentrant {
        updatePool();
        StakeInfo storage userStake = stakes[_msgSender()];
        uint256 pending = (userStake.amount * accRewardPerShare) / 1e12 - userStake.rewardDebt;
        if (pending == 0) revert ZeroAmount();

        userStake.rewardDebt = (userStake.amount * accRewardPerShare) / 1e12;
        _sendReward(_msgSender(), pending);
    }

    function setRewardRate(uint256 _rewardPerSecond) external onlyOwner {
        updatePool();
        rewardPerSecond = _rewardPerSecond;
    }

    function _sendReward(address to, uint256 amount) internal {
        rewardToken.mint(to, amount);
        emit RewardHarvested(to, amount);
    }
}

// -----------------------------------------------------------------------------
// MagnumVault: Over-Collateralized Lending & Borrowing Engine
// -----------------------------------------------------------------------------
contract MagnumVault is Context, ReentrancyGuard, Ownable {
    IERC20 public immutable collateralToken;
    IERC20 public immutable debtToken;

    uint256 public constant COLLATERAL_FACTOR = 75; // 75% LTV
    uint256 public constant LIQUIDATION_THRESHOLD = 80; // 80%
    uint256 public constant LIQUIDATION_DISCOUNT = 5; // 5% bonus to liquidator

    mapping(address => uint256) public collateralBalances;
    mapping(address => uint256) public debtBalances;

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event DebtBorrowed(address indexed user, uint256 amount);
    event DebtRepaid(address indexed user, uint256 amount);
    event Liquidated(address indexed borrower, address indexed liquidator, uint256 debtRepaid, uint256 collateralSeized);

    constructor(address _collateralToken, address _debtToken) Ownable(msg.sender) {
        if (_collateralToken == address(0) || _debtToken == address(0)) revert ZeroAddress();
        collateralToken = IERC20(_collateralToken);
        debtToken = IERC20(_debtToken);
    }

    function depositCollateral(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        collateralBalances[_msgSender()] += amount;
        collateralToken.transferFrom(_msgSender(), address(this), amount);
        emit CollateralDeposited(_msgSender(), amount);
    }

    function borrow(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        debtBalances[_msgSender()] += amount;

        uint256 healthFactor = getHealthFactor(_msgSender());
        if (healthFactor < 1e18) revert Undercollateralized(healthFactor);

        debtToken.transfer(_msgSender(), amount);
        emit DebtBorrowed(_msgSender(), amount);
    }

    function repay(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 currentDebt = debtBalances[_msgSender()];
        uint256 repayAmount = amount > currentDebt ? currentDebt : amount;

        debtBalances[_msgSender()] -= repayAmount;
        debtToken.transferFrom(_msgSender(), address(this), repayAmount);
        emit DebtRepaid(_msgSender(), repayAmount);
    }

    function liquidate(address borrower, uint256 debtToCover) external nonReentrant {
        uint256 healthFactor = getHealthFactor(borrower);
        if (healthFactor >= 1e18) revert HealthFactorSafe(healthFactor);

        uint256 borrowerDebt = debtBalances[borrower];
        if (debtToCover > borrowerDebt) debtToCover = borrowerDebt;

        uint256 collateralToSeize = debtToCover + ((debtToCover * LIQUIDATION_DISCOUNT) / 100);
        if (collateralToSeize > collateralBalances[borrower]) {
            collateralToSeize = collateralBalances[borrower];
        }

        debtBalances[borrower] -= debtToCover;
        collateralBalances[borrower] -= collateralToSeize;

        debtToken.transferFrom(_msgSender(), address(this), debtToCover);
        collateralToken.transfer(_msgSender(), collateralToSeize);

        emit Liquidated(borrower, _msgSender(), debtToCover, collateralToSeize);
    }

    function getHealthFactor(address user) public view returns (uint256) {
        uint256 debt = debtBalances[user];
        if (debt == 0) return type(uint256).max;

        uint256 collateralValue = collateralBalances[user];
        uint256 maxBorrow = (collateralValue * LIQUIDATION_THRESHOLD) / 100;

        return (maxBorrow * 1e18) / debt;
    }
}

// -----------------------------------------------------------------------------
// MagnumNexusManager: Governance Engine & Multi-Chain Operations Hub
// -----------------------------------------------------------------------------
contract MagnumNexusManager is Ownable {
    address public dexAddress;
    address public stakingAddress;
    address public vaultAddress;
    address public treasury;

    event ModuleUpdated(string indexed moduleName, address newAddress);
    event TreasuryUpdated(address newTreasury);

    constructor(address _treasury) Ownable(msg.sender) {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
    }

    function setModules(address _dex, address _staking, address _vault) external onlyOwner {
        dexAddress = _dex;
        stakingAddress = _staking;
        vaultAddress = _vault;
        emit ModuleUpdated("DEX", _dex);
        emit ModuleUpdated("Staking", _staking);
        emit ModuleUpdated("Vault", _vault);
    }

    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function pauseEcosystem() external onlyOwner {
        if (dexAddress != address(0)) Pausable(dexAddress).pause();
        if (stakingAddress != address(0)) Pausable(stakingAddress).pause();
    }

    function unpauseEcosystem() external onlyOwner {
        if (dexAddress != address(0)) Pausable(dexAddress).unpause();
        if (stakingAddress != address(0)) Pausable(stakingAddress).unpause();
    }
}
