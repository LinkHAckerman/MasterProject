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
    uint256 internal constant PERCENT_BPS = 10000;

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

interface IFlashBorrower {
    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data) external returns (bytes32);
}

interface IPriceOracle {
    function getAssetPrice(address asset) external view returns (uint256);
}

// -----------------------------------------------------------------------------
// Magnum Opus ERC20 Token with EIP-2612 Permit & Deflationary Mechanics
// -----------------------------------------------------------------------------
contract MagnumToken is Context, IERC20, IERC20Metadata, Ownable {
    string private _name;
    string private _symbol;
    uint8 private constant _DECIMALS = 18;
    uint256 private _totalSupply;
    uint256 public immutable maxSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) public nonces;

    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_,
        uint256 maxSupply_
    ) Ownable(_msgSender()) {
        if (maxSupply_ < initialSupply_) revert MaxSupplyReached();
        _name = name_;
        _symbol = symbol_;
        maxSupply = maxSupply_;

        _mint(_msgSender(), initialSupply_);

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

    function name() public view override returns (string memory) { return _name; }
    function symbol() public view override returns (string memory) { return _symbol; }
    function decimals() public pure override returns (uint8) { return _DECIMALS; }
    function totalSupply() public view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        if (_totalSupply + amount > maxSupply) revert MaxSupplyReached();
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
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
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signer = ecrecover(hash, v, r, s);
        if (signer == address(0) || signer != owner) revert InvalidSignature();

        _approve(owner, spender, value);
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) revert InsufficientBalance(fromBalance, amount);

        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        if (account == address(0)) revert ZeroAddress();
        _totalSupply += amount;
        unchecked {
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
        emit TokensMinted(account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        if (account == address(0)) revert ZeroAddress();
        uint256 accountBalance = _balances[account];
        if (accountBalance < amount) revert InsufficientBalance(accountBalance, amount);

        unchecked {
            _balances[account] = accountBalance - amount;
            _totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
        emit TokensBurned(account, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        if (owner == address(0) || spender == address(0)) revert ZeroAddress();
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert InsufficientAllowance(currentAllowance, amount);
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }
}

// -----------------------------------------------------------------------------
// Magnum Opus NFT Collection (ERC721 Artifacts with On-Chain Metadata & Royalties)
// -----------------------------------------------------------------------------
contract MagnumNFT is Context, IERC721, Ownable, ReentrancyGuard {
    string public name;
    string public symbol;
    uint256 public nextTokenId = 1;
    uint256 public immutable maxSupply;
    uint256 public mintPrice = 0.05 ether;
    string private _baseTokenURI;

    address public royaltyReceiver;
    uint96 public royaltyBasisPoints = 500; // 5%

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // On-chain attributes for dynamic NFT mechanics
    struct ArtifactTrait {
        uint16 powerLevel;
        uint16 tier;
        uint32 affinityScore;
        uint64 mintedAt;
    }
    mapping(uint256 => ArtifactTrait) public artifactTraits;

    event ArtifactMinted(address indexed recipient, uint256 indexed tokenId, uint16 tier, uint16 powerLevel);
    event RoyaltyUpdated(address indexed receiver, uint96 basisPoints);

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        string memory baseURI_
    ) Ownable(_msgSender()) {
        name = name_;
        symbol = symbol_;
        maxSupply = maxSupply_;
        _baseTokenURI = baseURI_;
        royaltyReceiver = _msgSender();
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == 0x2a55205a; // ERC2981 royalty interface
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

    function approve(address to, uint256 tokenId) public override {
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

    function setApprovalForAll(address operator, bool approved) public override {
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

    function safeTransferFrom(address from, address to, uint256 tokenId) public override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) public override {
        if (!_isApprovedOrOwner(_msgSender(), tokenId)) revert Unauthorized();
        _safeTransfer(from, to, tokenId, data);
    }

    function mintArtifact() external payable nonReentrant returns (uint256 tokenId) {
        if (msg.value < mintPrice) revert InsufficientBalance(msg.value, mintPrice);
        if (nextTokenId > maxSupply) revert MaxSupplyReached();

        tokenId = nextTokenId++;
        _mint(_msgSender(), tokenId);

        uint16 power = uint16((uint256(keccak256(abi.encodePacked(block.timestamp, tokenId, _msgSender()))) % 1000) + 1);
        uint16 tier = power > 900 ? 3 : (power > 500 ? 2 : 1);
        artifactTraits[tokenId] = ArtifactTrait({
            powerLevel: power,
            tier: tier,
            affinityScore: uint32(power * 10),
            mintedAt: uint64(block.timestamp)
        });

        emit ArtifactMinted(_msgSender(), tokenId, tier, power);
    }

    function royaltyInfo(uint256, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount) {
        receiver = royaltyReceiver;
        royaltyAmount = (salePrice * royaltyBasisPoints) / MagnumMath.PERCENT_BPS;
    }

    function setRoyaltyInfo(address receiver, uint96 basisPoints) external onlyOwner {
        if (receiver == address(0)) revert ZeroAddress();
        if (basisPoints > 2000) revert InvalidRoyaltyPercentage(); // Max 20%
        royaltyReceiver = receiver;
        royaltyBasisPoints = basisPoints;
        emit RoyaltyUpdated(receiver, basisPoints);
    }

    function setMintPrice(uint256 newPrice) external onlyOwner {
        mintPrice = newPrice;
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = payable(owner()).call{value: balance}("");
        if (!success) revert TransferFailed();
    }

    function _mint(address to, uint256 tokenId) internal {
        if (to == address(0)) revert ZeroAddress();
        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        if (ownerOf(tokenId) != from) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();

        delete _tokenApprovals[tokenId];
        unchecked {
            _balances[from] -= 1;
            _balances[to] += 1;
        }
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal {
        _transfer(from, to, tokenId);
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, data) returns (bytes4 retval) {
                if (retval != IERC721Receiver.onERC721Received.selector) revert TransferFailed();
            } catch {
                revert TransferFailed();
            }
        }
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender);
    }
}

// -----------------------------------------------------------------------------
// Automated Market Maker (AMM) Pair Pool
// -----------------------------------------------------------------------------
contract MagnumSwapPool is Context, ReentrancyGuard, Pausable {
    using MagnumMath for uint256;

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidityBalances;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to, uint256 liquidity);
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
        if (_token0 == address(0) || _token1 == address(0)) revert ZeroAddress();
        if (_token0 == _token1) revert IdenticalAddresses();
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
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

    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        address to
    ) external nonReentrant whenNotPaused returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        uint256 amount0;
        uint256 amount1;

        if (_reserve0 == 0 && _reserve1 == 0) {
            amount0 = amount0Desired;
            amount1 = amount1Desired;
            liquidity = (amount0 * amount1).sqrt() - MINIMUM_LIQUIDITY;
            totalLiquidity = MINIMUM_LIQUIDITY + liquidity;
            liquidityBalances[address(0)] = MINIMUM_LIQUIDITY; // Permanent lock
        } else {
            uint256 amount1Optimal = (amount0Desired * _reserve1) / _reserve0;
            if (amount1Optimal <= amount1Desired) {
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = (amount1Desired * _reserve0) / _reserve1;
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
            }
            liquidity = MagnumMath.min(
                (amount0 * totalLiquidity) / _reserve0,
                (amount1 * totalLiquidity) / _reserve1
            );
            if (liquidity == 0) revert InsufficientLiquidity();
            totalLiquidity += liquidity;
        }

        token0.transferFrom(_msgSender(), address(this), amount0);
        token1.transferFrom(_msgSender(), address(this), amount1);

        liquidityBalances[to] += liquidity;

        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)), _reserve0, _reserve1);
        emit Mint(_msgSender(), amount0, amount1, liquidity);
    }

    function removeLiquidity(uint256 liquidity, address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (liquidityBalances[_msgSender()] < liquidity) revert InsufficientBalance(liquidityBalances[_msgSender()], liquidity);
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();

        amount0 = (liquidity * _reserve0) / totalLiquidity;
        amount1 = (liquidity * _reserve1) / totalLiquidity;
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidity();

        liquidityBalances[_msgSender()] -= liquidity;
        totalLiquidity -= liquidity;

        token0.transfer(to, amount0);
        token1.transfer(to, amount1);

        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)), _reserve0, _reserve1);
        emit Burn(_msgSender(), amount0, amount1, to, liquidity);
    }

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external nonReentrant whenNotPaused {
        if (amount0Out == 0 && amount1Out == 0) revert ZeroAmount();
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        if (amount0Out >= _reserve0 || amount1Out >= _reserve1) revert InsufficientLiquidity();

        if (amount0Out > 0) token0.transfer(to, amount0Out);
        if (amount1Out > 0) token1.transfer(to, amount1Out);

        if (data.length > 0) {
            IFlashBorrower(to).onFlashLoan(_msgSender(), amount0Out > 0 ? address(token0) : address(token1), amount0Out > 0 ? amount0Out : amount1Out, 0, data);
        }

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        if (amount0In == 0 && amount1In == 0) revert ZeroAmount();

        // 0.3% trading fee verification
        uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
        uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);
        if (balance0Adjusted * balance1Adjusted < uint256(_reserve0) * uint256(_reserve1) * (1000**2)) {
            revert SlippageExceeded();
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(_msgSender(), amount0In, amount1In, amount0Out, amount1Out, to);
    }
}

// -----------------------------------------------------------------------------
// Multi-Tier Yield Staking & Farm Vault
// -----------------------------------------------------------------------------
contract MagnumVault is Context, Ownable, ReentrancyGuard, Pausable {
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    uint256 public rewardRatePerSecond; // Base rewards per second
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    struct StakeTier {
        uint32 lockDuration; // in seconds
        uint16 multiplierBps; // 10000 = 1.0x, 15000 = 1.5x
    }

    StakeTier[] public tiers;

    struct UserStake {
        uint256 amount;
        uint256 weightedAmount;
        uint256 rewardPerTokenPaid;
        uint256 rewards;
        uint64 unlockTimestamp;
        uint8 tierIndex;
    }

    mapping(address => UserStake[]) private _userStakes;
    uint256 public totalWeightedStaked;

    event Staked(address indexed user, uint256 indexed stakeId, uint256 amount, uint8 tierIndex, uint64 unlockTimestamp);
    event Withdrawn(address indexed user, uint256 indexed stakeId, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 newRate);

    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardRatePerSecond
    ) Ownable(_msgSender()) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardRatePerSecond = _rewardRatePerSecond;
        lastUpdateTime = block.timestamp;

        // Tiers: 0 -> Flexible (1.0x), 1 -> 30 days (1.25x), 2 -> 90 days (1.5x), 3 -> 365 days (2.0x)
        tiers.push(StakeTier({lockDuration: 0, multiplierBps: 10000}));
        tiers.push(StakeTier({lockDuration: 30 days, multiplierBps: 12500}));
        tiers.push(StakeTier({lockDuration: 90 days, multiplierBps: 15000}));
        tiers.push(StakeTier({lockDuration: 365 days, multiplierBps: 20000}));
    }

    modifier updateReward(address account, uint256 stakeIndex) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0) && _userStakes[account].length > stakeIndex) {
            UserStake storage stakeInfo = _userStakes[account][stakeIndex];
            stakeInfo.rewards = earned(account, stakeIndex);
            stakeInfo.rewardPerTokenPaid = rewardPerTokenStored;
        }
        _;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalWeightedStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (((block.timestamp - lastUpdateTime) * rewardRatePerSecond * 1e18) / totalWeightedStaked);
    }

    function earned(address account, uint256 stakeIndex) public view returns (uint256) {
        UserStake storage stakeInfo = _userStakes[account][stakeIndex];
        return stakeInfo.rewards + ((stakeInfo.weightedAmount * (rewardPerToken() - stakeInfo.rewardPerTokenPaid)) / 1e18);
    }

    function stake(uint256 amount, uint8 tierIndex) external nonReentrant whenNotPaused updateReward(_msgSender(), type(uint256).max) {
        if (amount == 0) revert ZeroAmount();
        if (tierIndex >= tiers.length) revert Unauthorized();

        StakeTier memory tier = tiers[tierIndex];
        uint256 weighted = (amount * tier.multiplierBps) / MagnumMath.PERCENT_BPS;

        stakingToken.transferFrom(_msgSender(), address(this), amount);

        totalWeightedStaked += weighted;
        uint64 unlockTime = uint64(block.timestamp + tier.lockDuration);

        _userStakes[_msgSender()].push(UserStake({
            amount: amount,
            weightedAmount: weighted,
            rewardPerTokenPaid: rewardPerTokenStored,
            rewards: 0,
            unlockTimestamp: unlockTime,
            tierIndex: tierIndex
        }));

        emit Staked(_msgSender(), _userStakes[_msgSender()].length - 1, amount, tierIndex, unlockTime);
    }

    function withdraw(uint256 stakeIndex) external nonReentrant updateReward(_msgSender(), stakeIndex) {
        if (stakeIndex >= _userStakes[_msgSender()].length) revert PositionLocked(0);
        UserStake storage stakeInfo = _userStakes[_msgSender()][stakeIndex];
        if (stakeInfo.amount == 0) revert ZeroAmount();
        if (block.timestamp < stakeInfo.unlockTimestamp) revert PositionLocked(stakeInfo.unlockTimestamp);

        uint256 amount = stakeInfo.amount;
        uint256 weighted = stakeInfo.weightedAmount;

        totalWeightedStaked -= weighted;
        stakeInfo.amount = 0;
        stakeInfo.weightedAmount = 0;

        stakingToken.transfer(_msgSender(), amount);
        emit Withdrawn(_msgSender(), stakeIndex, amount);
    }

    function claimReward(uint256 stakeIndex) external nonReentrant updateReward(_msgSender(), stakeIndex) {
        if (stakeIndex >= _userStakes[_msgSender()].length) revert PositionLocked(0);
        UserStake storage stakeInfo = _userStakes[_msgSender()][stakeIndex];
        uint256 reward = stakeInfo.rewards;
        if (reward > 0) {
            stakeInfo.rewards = 0;
            rewardToken.transfer(_msgSender(), reward);
            emit RewardClaimed(_msgSender(), reward);
        }
    }

    function getUserStakeCount(address user) external view returns (uint256) {
        return _userStakes[user].length;
    }

    function getUserStake(address user, uint256 index) external view returns (
        uint256 amount,
        uint256 weightedAmount,
        uint256 pendingRewards,
        uint64 unlockTimestamp,
        uint8 tierIndex
    ) {
        UserStake storage stakeInfo = _userStakes[user][index];
        return (
            stakeInfo.amount,
            stakeInfo.weightedAmount,
            earned(user, index),
            stakeInfo.unlockTimestamp,
            stakeInfo.tierIndex
        );
    }

    function setRewardRate(uint256 newRate) external onlyOwner updateReward(address(0), 0) {
        rewardRatePerSecond = newRate;
        emit RewardRateUpdated(newRate);
    }
}

// -----------------------------------------------------------------------------
// DeFi Lending & Collateral Protocol with Flash Loan Facility
// -----------------------------------------------------------------------------
contract MagnumLendingEngine is Context, Ownable, ReentrancyGuard, Pausable {
    using MagnumMath for uint256;

    IERC20 public immutable collateralToken;
    IERC20 public immutable borrowToken;
    IPriceOracle public priceOracle;

    uint256 public constant COLLATERAL_FACTOR = 7500; // 75% LTV (Loan-To-Value)
    uint256 public constant LIQUIDATION_THRESHOLD = 8000; // 80% liquidation threshold
    uint256 public constant LIQUIDATION_BONUS = 500; // 5% liquidation bonus
    uint256 public constant FLASH_LOAN_FEE_BPS = 9; // 0.09% fee
    bytes32 private constant FLASH_LOAN_CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    struct AccountState {
        uint256 collateralDeposited;
        uint256 borrowPrincipal;
        uint256 lastInterestBlock;
    }

    mapping(address => AccountState) public accounts;
    uint256 public totalCollateral;
    uint256 public totalBorrows;

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(address indexed borrower, address indexed liquidator, uint256 repayAmount, uint256 collateralClaimed);
    event FlashLoanExecuted(address indexed borrower, address indexed token, uint256 amount, uint256 fee);

    constructor(address _collateralToken, address _borrowToken, address _priceOracle) Ownable(_msgSender()) {
        collateralToken = IERC20(_collateralToken);
        borrowToken = IERC20(_borrowToken);
        priceOracle = IPriceOracle(_priceOracle);
    }

    function depositCollateral(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        accounts[_msgSender()].collateralDeposited += amount;
        totalCollateral += amount;

        collateralToken.transferFrom(_msgSender(), address(this), amount);
        emit CollateralDeposited(_msgSender(), amount);
    }

    function withdrawCollateral(uint256 amount) external nonReentrant {
        AccountState storage state = accounts[_msgSender()];
        if (state.collateralDeposited < amount) revert InsufficientBalance(state.collateralDeposited, amount);

        state.collateralDeposited -= amount;
        totalCollateral -= amount;

        uint256 health = calculateHealthFactor(_msgSender());
        if (health < 1e18 && state.borrowPrincipal > 0) revert Undercollateralized(health);

        collateralToken.transfer(_msgSender(), amount);
        emit CollateralWithdrawn(_msgSender(), amount);
    }

    function borrow(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        AccountState storage state = accounts[_msgSender()];
        state.borrowPrincipal += amount;
        totalBorrows += amount;

        uint256 health = calculateHealthFactor(_msgSender());
        if (health < 1e18) revert Undercollateralized(health);

        borrowToken.transfer(_msgSender(), amount);
        emit Borrowed(_msgSender(), amount);
    }

    function repay(uint256 amount) external nonReentrant {
        AccountState storage state = accounts[_msgSender()];
        uint256 toRepay = MagnumMath.min(amount, state.borrowPrincipal);
        if (toRepay == 0) revert ZeroAmount();

        state.borrowPrincipal -= toRepay;
        totalBorrows -= toRepay;

        borrowToken.transferFrom(_msgSender(), address(this), toRepay);
        emit Repaid(_msgSender(), toRepay);
    }

    function liquidate(address borrower, uint256 repayAmount) external nonReentrant {
        uint256 health = calculateHealthFactor(borrower);
        if (health >= 1e18) revert HealthFactorSafe(health);

        AccountState storage state = accounts[borrower];
        uint256 debtToCover = MagnumMath.min(repayAmount, state.borrowPrincipal / 2); // Max 50% close factor
        if (debtToCover == 0) revert ZeroAmount();

        uint256 collateralPrice = priceOracle.getAssetPrice(address(collateralToken));
        uint256 borrowPrice = priceOracle.getAssetPrice(address(borrowToken));

        // Collateral value to seize: (debtToCover * borrowPrice / collateralPrice) * (1 + bonus)
        uint256 collateralEquivalent = (debtToCover * borrowPrice) / collateralPrice;
        uint256 collateralSeized = (collateralEquivalent * (MagnumMath.PERCENT_BPS + LIQUIDATION_BONUS)) / MagnumMath.PERCENT_BPS;
        if (collateralSeized > state.collateralDeposited) {
            collateralSeized = state.collateralDeposited;
        }

        state.borrowPrincipal -= debtToCover;
        state.collateralDeposited -= collateralSeized;
        totalBorrows -= debtToCover;
        totalCollateral -= collateralSeized;

        borrowToken.transferFrom(_msgSender(), address(this), debtToCover);
        collateralToken.transfer(_msgSender(), collateralSeized);

        emit Liquidated(borrower, _msgSender(), debtToCover, collateralSeized);
    }

    function flashLoan(
        address receiverAddress,
        address token,
        uint256 amount,
        bytes calldata data
    ) external nonReentrant returns (bool) {
        if (token != address(borrowToken)) revert Unauthorized();
        uint256 fee = (amount * FLASH_LOAN_FEE_BPS) / MagnumMath.PERCENT_BPS;
        uint256 balanceBefore = borrowToken.balanceOf(address(this));
        if (balanceBefore < amount) revert InsufficientLiquidity();

        borrowToken.transfer(receiverAddress, amount);

        bytes32 callbackResult = IFlashBorrower(receiverAddress).onFlashLoan(_msgSender(), token, amount, fee, data);
        if (callbackResult != FLASH_LOAN_CALLBACK_SUCCESS) revert FlashLoanFailed();

        uint256 balanceAfter = borrowToken.balanceOf(address(this));
        if (balanceAfter < balanceBefore + fee) revert InsufficientBalance(balanceAfter, balanceBefore + fee);

        emit FlashLoanExecuted(receiverAddress, token, amount, fee);
        return true;
    }

    function calculateHealthFactor(address user) public view returns (uint256) {
        AccountState storage state = accounts[user];
        if (state.borrowPrincipal == 0) return type(uint256).max;

        uint256 collateralPrice = priceOracle.getAssetPrice(address(collateralToken));
        uint256 borrowPrice = priceOracle.getAssetPrice(address(borrowToken));

        uint256 collateralValue = (state.collateralDeposited * collateralPrice) / 1e18;
        uint256 borrowValue = (state.borrowPrincipal * borrowPrice) / 1e18;

        uint256 adjustedCollateral = (collateralValue * LIQUIDATION_THRESHOLD) / MagnumMath.PERCENT_BPS;
        return (adjustedCollateral * 1e18) / borrowValue;
    }

    function setOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert ZeroAddress();
        priceOracle = IPriceOracle(newOracle);
    }
}

// -----------------------------------------------------------------------------
// Master Nexus Controller: Ecosystem Orchestrator & Governance Registry
// -----------------------------------------------------------------------------
contract MagnumNexusController is Ownable {
    MagnumToken public immutable opusToken;
    MagnumNFT public immutable artifactNFT;
    MagnumVault public immutable stakingVault;
    MagnumLendingEngine public immutable lendingEngine;

    mapping(bytes32 => address) public protocolComponents;

    event ComponentRegistered(bytes32 indexed key, address indexed componentAddress);
    event EmergencyActionExecuted(bytes32 actionId, address target);

    constructor(
        address payable opusTokenAddress,
        address payable artifactNFTAddress,
        address payable stakingVaultAddress,
        address payable lendingEngineAddress
    ) Ownable(_msgSender()) {
        opusToken = MagnumToken(opusTokenAddress);
        artifactNFT = MagnumNFT(artifactNFTAddress);
        stakingVault = MagnumVault(stakingVaultAddress);
        lendingEngine = MagnumLendingEngine(lendingEngineAddress);

        protocolComponents[keccak256("OPUS_TOKEN")] = opusTokenAddress;
        protocolComponents[keccak256("ARTIFACT_NFT")] = artifactNFTAddress;
        protocolComponents[keccak256("STAKING_VAULT")] = stakingVaultAddress;
        protocolComponents[keccak256("LENDING_ENGINE")] = lendingEngineAddress;
    }

    function registerComponent(string calldata name, address componentAddress) external onlyOwner {
        if (componentAddress == address(0)) revert ZeroAddress();
        bytes32 key = keccak256(bytes(name));
        protocolComponents[key] = componentAddress;
        emit ComponentRegistered(key, componentAddress);
    }

    function executeNexusCall(address target, bytes calldata data) external payable onlyOwner returns (bytes memory) {
        (bool success, bytes memory result) = target.call{value: msg.value}(data);
        if (!success) revert TransferFailed();
        emit EmergencyActionExecuted(keccak256(data), target);
        return result;
    }
}
