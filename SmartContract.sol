// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MAGNUM OPUS // Nexus DeFi, AMM & Yield Engine
 * @notice Autonomous liquidity hub, flash-swap pool, yield aggregator, and hybrid ERC-20 / ERC-721 ecosystem.
 * @dev Implements gas-efficient bitpacking, transient-style reentrancy guards, EIP-2612 permits, and EIP-2981 royalties.
 */

// =========================================================================
// INTERFACES & STANDARDS
// =========================================================================

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

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC721 is IERC165 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

interface IERC2981 is IERC165 {
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount);
}

interface IFlashBorrower {
    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data) external returns (bytes32);
}

// =========================================================================
// ERROR DEFINITIONS
// =========================================================================

error ReentrantCall();
error Unauthorized();
error ZeroAddress();
error DeadlineExpired();
error InsufficientBalance(uint256 available, uint256 required);
error InsufficientAllowance(uint256 available, uint256 required);
error InsufficientLiquidity();
error InsufficientInputAmount();
error InsufficientOutputAmount();
error InvariantViolated(uint256 expected, uint256 actual);
error InvalidFlashCallback();
error TokenLocked(uint256 unlockTimestamp);
error MintLimitExceeded();
error NonexistentToken();

// =========================================================================
// SECURITY & BASE UTILITIES
// =========================================================================

abstract contract ReentrancyGuard {
    uint256 private _status;

    constructor() {
        _status = 1;
    }

    modifier nonReentrant() {
        if (_status != 1) revert ReentrantCall();
        _status = 2;
        _;
        _status = 1;
    }
}

abstract contract Ownable2Step {
    address private _owner;
    address private _pendingOwner;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert Unauthorized();
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(_owner, newOwner);
    }

    function acceptOwnership() public virtual {
        if (msg.sender != _pendingOwner) revert Unauthorized();
        emit OwnershipTransferred(_owner, _pendingOwner);
        _owner = _pendingOwner;
        _pendingOwner = address(0);
    }
}

// =========================================================================
// CORE TOKEN: MAGNUM NEXUS TOKEN (ERC-20 + EIP-2612 PERMIT)
// =========================================================================

contract MagnumNexusToken is IERC20Metadata, Ownable2Step {
    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;
    uint256 private _totalSupply;
    uint256 public immutable maxSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) public nonces;

    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);

    constructor(string memory name_, string memory symbol_, uint256 initialSupply, uint256 maxSupply_)
        Ownable2Step(msg.sender)
    {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
        maxSupply = maxSupply_;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name_)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );

        _mint(msg.sender, initialSupply);
    }

    function name() public view override returns (string memory) { return _name; }
    function symbol() public view override returns (string memory) { return _symbol; }
    function decimals() public view override returns (uint8) { return _decimals; }
    function totalSupply() public view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }

    function transfer(address to, uint256 value) public override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) public override returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) revert InsufficientAllowance(currentAllowance, value);
            unchecked {
                _approve(from, msg.sender, currentAllowance - value);
            }
        }
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
    ) external {
        if (block.timestamp > deadline) revert DeadlineExpired();

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline));
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signer = ecrecover(hash, v, r, s);
        if (signer == address(0) || signer != owner) revert Unauthorized();

        _approve(owner, spender, value);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        if (_totalSupply + amount > maxSupply) revert MintLimitExceeded();
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (to == address(0)) revert ZeroAddress();
        uint256 fromBalance = _balances[from];
        if (fromBalance < value) revert InsufficientBalance(fromBalance, value);

        unchecked {
            _balances[from] = fromBalance - value;
            _balances[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function _mint(address account, uint256 value) internal {
        if (account == address(0)) revert ZeroAddress();
        _totalSupply += value;
        unchecked {
            _balances[account] += value;
        }
        emit Transfer(address(0), account, value);
        emit Mint(account, value);
    }

    function _burn(address account, uint256 value) internal {
        uint256 accountBalance = _balances[account];
        if (accountBalance < value) revert InsufficientBalance(accountBalance, value);
        unchecked {
            _balances[account] = accountBalance - value;
            _totalSupply -= value;
        }
        emit Transfer(account, address(0), value);
        emit Burn(account, value);
    }

    function _approve(address owner, address spender, uint256 value) internal {
        if (owner == address(0) || spender == address(0)) revert ZeroAddress();
        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }
}

// =========================================================================
// AMM LIQUIDITY POOL & FLASH SWAP ENGINE
// =========================================================================

contract MagnumSwapPair is ReentrancyGuard {
    address public immutable token0;
    address public immutable token1;
    address public immutable factory;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast;

    uint256 public totalLpSupply;
    mapping(address => uint256) public lpBalances;

    bytes32 private constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");
    uint256 private constant FEE_DENOMINATOR = 10000;
    uint256 public swapFeeBps = 30; // 0.30% fee

    event MintLiquidity(address indexed sender, uint256 amount0, uint256 amount1);
    event BurnLiquidity(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to);
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor(address _token0, address _token1) {
        factory = msg.sender;
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert Unauthorized();
    }

    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed;
        unchecked {
            timeElapsed = blockTimestamp - blockTimestampLast;
        }

        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            unchecked {
                price0CumulativeLast += uint256((uint256(_reserve1) << 112) / _reserve0) * timeElapsed;
                price1CumulativeLast += uint256((uint256(_reserve0) << 112) / _reserve1) * timeElapsed;
            }
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    function mintLiquidity(address to) external nonReentrant returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        if (totalLpSupply == 0) {
            liquidity = _sqrt(amount0 * amount1);
            if (liquidity <= 1000) revert InsufficientLiquidity();
            totalLpSupply = liquidity;
            lpBalances[address(0)] = 1000; // Permanently lock first 1000 minimum liquidity
            liquidity -= 1000;
            lpBalances[to] = liquidity;
        } else {
            uint256 liq0 = (amount0 * totalLpSupply) / _reserve0;
            uint256 liq1 = (amount1 * totalLpSupply) / _reserve1;
            liquidity = liq0 < liq1 ? liq0 : liq1;
            if (liquidity == 0) revert InsufficientLiquidity();
            totalLpSupply += liquidity;
            lpBalances[to] += liquidity;
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        kLast = uint256(reserve0) * reserve1;
        emit MintLiquidity(msg.sender, amount0, amount1);
    }

    function burnLiquidity(address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        uint256 liquidity = lpBalances[address(this)];
        if (liquidity == 0) revert InsufficientLiquidity();

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        amount0 = (liquidity * balance0) / totalLpSupply;
        amount1 = (liquidity * balance1) / totalLpSupply;
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidity();

        lpBalances[address(this)] = 0;
        totalLpSupply -= liquidity;

        _safeTransfer(token0, to, amount0);
        _safeTransfer(token1, to, amount1);

        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));

        _update(balance0, balance1, reserve0, reserve1);
        kLast = uint256(reserve0) * reserve1;
        emit BurnLiquidity(msg.sender, amount0, amount1, to);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
        if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutputAmount();
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        if (amount0Out >= _reserve0 || amount1Out >= _reserve1) revert InsufficientLiquidity();

        if (amount0Out > 0) _safeTransfer(token0, to, amount0Out);
        if (amount1Out > 0) _safeTransfer(token1, to, amount1Out);

        if (data.length > 0) {
            address flashToken = amount0Out > 0 ? token0 : token1;
            uint256 flashAmount = amount0Out > 0 ? amount0Out : amount1Out;
            uint256 flashFee = (flashAmount * swapFeeBps) / FEE_DENOMINATOR;
            bytes32 returnVal = IFlashBorrower(to).onFlashLoan(msg.sender, flashToken, flashAmount, flashFee, data);
            if (returnVal != CALLBACK_SUCCESS) revert InvalidFlashCallback();
        }

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        if (amount0In == 0 && amount1In == 0) revert InsufficientInputAmount();

        uint256 balance0Adjusted = (balance0 * FEE_DENOMINATOR) - (amount0In * swapFeeBps);
        uint256 balance1Adjusted = (balance1 * FEE_DENOMINATOR) - (amount1In * swapFeeBps);
        if (balance0Adjusted * balance1Adjusted < uint256(_reserve0) * _reserve1 * (FEE_DENOMINATOR**2)) {
            revert InvariantViolated(uint256(_reserve0) * _reserve1, balance0 * balance1);
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function sync() external nonReentrant {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }

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

// =========================================================================
// FACTORY FOR PAIR CREATION & REGISTRY
// =========================================================================

contract MagnumSwapFactory is Ownable2Step {
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;
    address public feeTo;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 pairIndex);

    constructor(address feeReceiver) Ownable2Step(msg.sender) {
        feeTo = feeReceiver;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function setFeeTo(address newFeeTo) external onlyOwner {
        feeTo = newFeeTo;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (tokenA == tokenB) revert Unauthorized();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert ZeroAddress();
        if (getPair[token0][token1] != address(0)) revert Unauthorized();

        MagnumSwapPair newPair = new MagnumSwapPair(token0, token1);
        pair = address(newPair);

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}

// =========================================================================
// ERC-721 PROTOCOL GENESIS NFT (EIP-721 + EIP-2981 ROYALTY)
// =========================================================================

contract MagnumGenesisPass is IERC721, IERC2981, Ownable2Step {
    string public name;
    string public symbol;
    uint256 public nextTokenId = 1;
    uint256 public immutable maxSupply;
    uint256 public mintPrice = 0.05 ether;

    address public royaltyReceiver;
    uint96 public royaltyFraction = 500; // 5.00%
    string private baseTokenURI;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // Token boost factor for yield calculations: (tokenId => yield multiplier in basis points, e.g. 12500 = 1.25x)
    mapping(uint256 => uint256) public yieldBoostMultiplier;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        string memory baseURI_
    ) Ownable2Step(msg.sender) {
        name = name_;
        symbol = symbol_;
        maxSupply = maxSupply_;
        baseTokenURI = baseURI_;
        royaltyReceiver = msg.sender;
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC2981).interfaceId;
    }

    function balanceOf(address owner_) public view override returns (uint256) {
        if (owner_ == address(0)) revert ZeroAddress();
        return _balances[owner_];
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        address owner_ = _owners[tokenId];
        if (owner_ == address(0)) revert NonexistentToken();
        return owner_;
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        if (_owners[tokenId] == address(0)) revert NonexistentToken();
        return string(abi.encodePacked(baseTokenURI, _toString(tokenId), ".json"));
    }

    function setBaseURI(string memory newURI) external onlyOwner {
        baseTokenURI = newURI;
    }

    function setMintPrice(uint256 newPrice) external onlyOwner {
        mintPrice = newPrice;
    }

    function setRoyaltyInfo(address receiver, uint96 fraction) external onlyOwner {
        royaltyReceiver = receiver;
        royaltyFraction = fraction;
    }

    function royaltyInfo(uint256, uint256 salePrice) external view override returns (address, uint256) {
        uint256 royaltyAmount = (salePrice * royaltyFraction) / 10000;
        return (royaltyReceiver, royaltyAmount);
    }

    function mintGenesis() external payable returns (uint256 tokenId) {
        if (msg.value < mintPrice) revert InsufficientBalance(msg.value, mintPrice);
        tokenId = nextTokenId;
        if (tokenId > maxSupply) revert MintLimitExceeded();

        nextTokenId = tokenId + 1;
        _balances[msg.sender] += 1;
        _owners[tokenId] = msg.sender;

        // Assign algorithmic dynamic boost tiers: Rare (1.50x), Epic (1.75x), Legendary (2.50x)
        if (tokenId % 50 == 0) {
            yieldBoostMultiplier[tokenId] = 25000; // 2.5x
        } else if (tokenId % 10 == 0) {
            yieldBoostMultiplier[tokenId] = 17500; // 1.75x
        } else {
            yieldBoostMultiplier[tokenId] = 12000; // 1.2x
        }

        emit Transfer(address(0), msg.sender, tokenId);
    }

    function approve(address to, uint256 tokenId) public override {
        address owner_ = ownerOf(tokenId);
        if (msg.sender != owner_ && !isApprovedForAll(owner_, msg.sender)) revert Unauthorized();
        _tokenApprovals[tokenId] = to;
        emit Approval(owner_, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view override returns (address) {
        if (_owners[tokenId] == address(0)) revert NonexistentToken();
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public override {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner_, address operator) public view override returns (bool) {
        return _operatorApprovals[owner_][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        address owner_ = ownerOf(tokenId);
        if (owner_ != from) revert Unauthorized();
        if (msg.sender != owner_ && msg.sender != getApproved(tokenId) && !isApprovedForAll(owner_, msg.sender)) {
            revert Unauthorized();
        }
        if (to == address(0)) revert ZeroAddress();

        delete _tokenApprovals[tokenId];
        unchecked {
            _balances[from] -= 1;
            _balances[to] += 1;
        }
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) public override {
        transferFrom(from, to, tokenId);
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
                if (retval != IERC721Receiver.onERC721Received.selector) revert Unauthorized();
            } catch {
                revert Unauthorized();
            }
        }
    }

    function withdrawTreasury(address payable recipient) external onlyOwner {
        recipient.transfer(address(this).balance);
    }

    function _toString(uint256 value) private pure returns (string memory) {
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

// =========================================================================
// STAKING & MULTI-TIER YIELD VAULT (WITH NFT BOOST & LOCK MULTIPLIERS)
// =========================================================================

contract MagnumYieldVault is ReentrancyGuard, Ownable2Step {
    IERC20 public immutable stakingToken;
    MagnumNexusToken public immutable rewardToken;
    MagnumGenesisPass public immutable genesisNFT;

    struct StakeInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lockedUntil;
        uint256 stakedNftId; // 0 if no NFT staked
    }

    uint256 public rewardPerSecond = 1e18; // 1 reward token per second base distribution
    uint256 public lastRewardTime;
    uint256 public accRewardPerShare;
    uint256 public totalStakedShares;

    mapping(address => StakeInfo) public stakes;

    event Staked(address indexed user, uint256 amount, uint256 lockDuration, uint256 nftId);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);

    constructor(
        address _stakingToken,
        address _rewardToken,
        address _genesisNft
    ) Ownable2Step(msg.sender) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = MagnumNexusToken(_rewardToken);
        genesisNFT = MagnumGenesisPass(_genesisNft);
        lastRewardTime = block.timestamp;
    }

    function updatePool() public {
        if (block.timestamp <= lastRewardTime) return;
        if (totalStakedShares == 0) {
            lastRewardTime = block.timestamp;
            return;
        }
        uint256 duration = block.timestamp - lastRewardTime;
        uint256 reward = duration * rewardPerSecond;
        accRewardPerShare += (reward * 1e12) / totalStakedShares;
        lastRewardTime = block.timestamp;
    }

    function stake(uint256 amount, uint256 lockWeeks, uint256 nftId) external nonReentrant {
        if (amount == 0) revert InsufficientInputAmount();
        updatePool();

        StakeInfo storage user = stakes[msg.sender];
        if (user.amount > 0) {
            uint256 pending = ((user.amount * accRewardPerShare) / 1e12) - user.rewardDebt;
            if (pending > 0) {
                rewardToken.mint(msg.sender, pending);
                emit RewardClaimed(msg.sender, pending);
            }
        }

        // Handle NFT boost
        if (nftId > 0 && user.stakedNftId == 0) {
            genesisNFT.transferFrom(msg.sender, address(this), nftId);
            user.stakedNftId = nftId;
        }

        uint256 boostBps = 10000; // Base 100%
        if (user.stakedNftId > 0) {
            boostBps = genesisNFT.yieldBoostMultiplier(user.stakedNftId);
        }
        // Lock bonus: +10% per locked week up to 52 weeks (+520% max)
        if (lockWeeks > 52) lockWeeks = 52;
        boostBps += lockWeeks * 1000;

        uint256 effectiveShares = (amount * boostBps) / 10000;
        stakingToken.transferFrom(msg.sender, address(this), amount);

        user.amount += effectiveShares;
        user.lockedUntil = block.timestamp + (lockWeeks * 1 weeks);
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e12;
        totalStakedShares += effectiveShares;

        emit Staked(msg.sender, amount, lockWeeks, nftId);
    }

    function withdraw(uint256 shareAmount) external nonReentrant {
        StakeInfo storage user = stakes[msg.sender];
        if (user.amount < shareAmount) revert InsufficientBalance(user.amount, shareAmount);
        if (block.timestamp < user.lockedUntil) revert TokenLocked(user.lockedUntil);

        updatePool();
        uint256 pending = ((user.amount * accRewardPerShare) / 1e12) - user.rewardDebt;
        if (pending > 0) {
            rewardToken.mint(msg.sender, pending);
            emit RewardClaimed(msg.sender, pending);
        }

        user.amount -= shareAmount;
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e12;
        totalStakedShares -= shareAmount;

        stakingToken.transfer(msg.sender, shareAmount);

        if (user.amount == 0 && user.stakedNftId > 0) {
            uint256 returningNftId = user.stakedNftId;
            user.stakedNftId = 0;
            genesisNFT.safeTransferFrom(address(this), msg.sender, returningNftId);
        }

        emit Withdrawn(msg.sender, shareAmount);
    }

    function pendingReward(address userAddress) external view returns (uint256) {
        StakeInfo memory user = stakes[userAddress];
        uint256 tempAccRewardPerShare = accRewardPerShare;
        if (block.timestamp > lastRewardTime && totalStakedShares != 0) {
            uint256 duration = block.timestamp - lastRewardTime;
            uint256 reward = duration * rewardPerSecond;
            tempAccRewardPerShare += (reward * 1e12) / totalStakedShares;
        }
        return ((user.amount * tempAccRewardPerShare) / 1e12) - user.rewardDebt;
    }

    function setEmissionRate(uint256 newRate) external onlyOwner {
        updatePool();
        rewardPerSecond = newRate;
    }
}
