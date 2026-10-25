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
// Standard Token Interfaces
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

interface IERC2612 {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function nonces(address owner) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
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

// -----------------------------------------------------------------------------
// 1. Native Platform Token (MOPUS) - ERC20 + EIP-2612 Permits + Burnable
// -----------------------------------------------------------------------------
contract MagnumOpusToken is Context, Ownable, Pausable, IERC20Metadata, IERC2612 {
    string private _name = "Magnum Opus Protocol";
    string private _symbol = "MOPUS";
    uint8 private constant _DECIMALS = 18;
    uint256 private _totalSupply;
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) private _nonces;

    bytes32 public immutable INITIAL_CHAIN_ID;
    bytes32 public immutable INITIAL_DOMAIN_SEPARATOR;

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    constructor(address initialOwner, uint256 initialSupply)
        Ownable(initialOwner)
    {
        require(initialSupply * (10 ** _DECIMALS) <= MAX_SUPPLY, "Exceeds max supply");
        INITIAL_CHAIN_ID = bytes32(block.chainid);
        INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();
        _mint(initialOwner, initialSupply * (10 ** _DECIMALS));
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

    function transfer(address recipient, uint256 amount) public override whenNotPaused returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address ownerAddr, address spender) public view override returns (uint256) {
        return _allowances[ownerAddr][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override whenNotPaused returns (bool) {
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

    function mint(address to, uint256 amount) external onlyOwner whenNotPaused {
        if (_totalSupply + amount > MAX_SUPPLY) revert MaxSupplyReached();
        _mint(to, amount);
    }

    function burn(uint256 amount) external whenNotPaused {
        _burn(_msgSender(), amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function nonces(address ownerAddr) public view override returns (uint256) {
        return _nonces[ownerAddr];
    }

    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return block.chainid == uint256(INITIAL_CHAIN_ID) ? INITIAL_DOMAIN_SEPARATOR : _computeDomainSeparator();
    }

    function _computeDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(_name)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function permit(
        address ownerAddr,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        if (block.timestamp > deadline) revert SignatureExpired();
        if (ownerAddr == address(0)) revert ZeroAddress();

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, ownerAddr, spender, value, _nonces[ownerAddr]++, deadline)
        );
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        address signer = ecrecover(hash, v, r, s);
        if (signer == address(0) || signer != ownerAddr) revert InvalidSignature();

        _approve(ownerAddr, spender, value);
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
        unchecked {
            _balances[account] += amount;
        }
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

    function _approve(address ownerAddr, address spender, uint256 amount) internal {
        if (ownerAddr == address(0) || spender == address(0)) revert ZeroAddress();
        _allowances[ownerAddr][spender] = amount;
        emit Approval(ownerAddr, spender, amount);
    }
}

// -----------------------------------------------------------------------------
// 2. Magnum Opus Artifacts - Advanced Generative NFT with EIP-2981 Royalties
// -----------------------------------------------------------------------------
contract MagnumOpusNFT is Context, Ownable, IERC721, IERC2981 {
    string public name = "Magnum Opus Artifacts";
    string public symbol = "MOART";

    uint256 public nextTokenId = 1;
    uint256 public constant MAX_COLLECTION_SIZE = 10_000;
    uint256 public mintPrice = 0.05 ether;

    address public royaltyReceiver;
    uint96 public royaltyFractionBps = 500; // 5%

    string private _baseTokenURI;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint256 => string) private _tokenCustomURIs;
    mapping(uint256 => uint8) public rarityTier;

    event Minted(address indexed to, uint256 indexed tokenId, uint8 tier);
    event MintPriceUpdated(uint256 newPrice);
    event RoyaltyUpdated(address indexed receiver, uint96 bps);

    constructor(address initialOwner, string memory baseURI)
        Ownable(initialOwner)
    {
        royaltyReceiver = initialOwner;
        _baseTokenURI = baseURI;
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC2981).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    function balanceOf(address ownerAddr) public view override returns (uint256) {
        if (ownerAddr == address(0)) revert ZeroAddress();
        return _balances[ownerAddr];
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        address tokenOwner = _owners[tokenId];
        if (tokenOwner == address(0)) revert ZeroAddress();
        return tokenOwner;
    }

    function royaltyInfo(uint256, uint256 salePrice) external view override returns (address, uint256) {
        uint256 royaltyAmount = (salePrice * royaltyFractionBps) / 10000;
        return (royaltyReceiver, royaltyAmount);
    }

    function setRoyaltyInfo(address receiver, uint96 bps) external onlyOwner {
        if (receiver == address(0)) revert ZeroAddress();
        if (bps > 2000) revert InvalidRoyaltyPercentage(); // max 20%
        royaltyReceiver = receiver;
        royaltyFractionBps = bps;
        emit RoyaltyUpdated(receiver, bps);
    }

    function setMintPrice(uint256 newPrice) external onlyOwner {
        mintPrice = newPrice;
        emit MintPriceUpdated(newPrice);
    }

    function setBaseURI(string memory newURI) external onlyOwner {
        _baseTokenURI = newURI;
    }

    function mintArtifact(address to, string calldata customURI) external payable returns (uint256) {
        if (msg.value < mintPrice) revert InsufficientBalance(msg.value, mintPrice);
        if (nextTokenId > MAX_COLLECTION_SIZE) revert MaxSupplyReached();

        uint256 tokenId = nextTokenId++;
        uint8 calculatedTier = uint8((uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, tokenId))) % 5) + 1);
        rarityTier[tokenId] = calculatedTier;

        _mint(to, tokenId);
        if (bytes(customURI).length > 0) {
            _tokenCustomURIs[tokenId] = customURI;
        }

        emit Minted(to, tokenId, calculatedTier);
        return tokenId;
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        if (_owners[tokenId] == address(0)) revert ZeroAddress();
        if (bytes(_tokenCustomURIs[tokenId]).length > 0) {
            return _tokenCustomURIs[tokenId];
        }
        return string(abi.encodePacked(_baseTokenURI, _toString(tokenId), ".json"));
    }

    function approve(address to, uint256 tokenId) public override {
        address tokenOwner = ownerOf(tokenId);
        if (to == tokenOwner) revert IdenticalAddresses();
        if (_msgSender() != tokenOwner && !isApprovedForAll(tokenOwner, _msgSender())) revert Unauthorized();

        _tokenApprovals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view override returns (address) {
        if (_owners[tokenId] == address(0)) revert ZeroAddress();
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public override {
        if (operator == _msgSender()) revert IdenticalAddresses();
        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    function isApprovedForAll(address tokenOwner, address operator) public view override returns (bool) {
        return _operatorApprovals[tokenOwner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        if (!_isApprovedOrOwner(_msgSender(), tokenId)) revert Unauthorized();
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override {
        if (!_isApprovedOrOwner(_msgSender(), tokenId)) revert Unauthorized();
        _safeTransfer(from, to, tokenId, data);
    }

    function withdrawProceeds() external onlyOwner {
        uint256 bal = address(this).balance;
        if (bal == 0) revert ZeroAmount();
        (bool success, ) = payable(owner()).call{value: bal}("");
        require(success, "Transfer failed");
    }

    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal {
        _transfer(from, to, tokenId);
        if (!_checkOnERC721Received(from, to, tokenId, data)) {
            revert("ERC721: transfer to non ERC721Receiver implementer");
        }
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

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address tokenOwner = ownerOf(tokenId);
        return (spender == tokenOwner || isApprovedForAll(tokenOwner, spender) || getApproved(tokenId) == spender);
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data) private returns (bool) {
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch {
                return false;
            }
        }
        return true;
    }

    function _toString(uint256 value) internal pure returns (string memory) {
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

// -----------------------------------------------------------------------------
// 3. Staking Vault - Multi-Tier Yield Engine with Lock Multipliers
// -----------------------------------------------------------------------------
contract StakingVault is Context, Ownable, ReentrancyGuard, Pausable {
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    uint256 public rewardRatePerSecond;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public totalWeightedStake;

    struct StakePosition {
        uint256 principal;
        uint256 weightedAmount;
        uint256 lockDuration;
        uint256 startTime;
        uint256 unlockTime;
        uint256 rewardDebt;
        uint256 accruedRewards;
    }

    mapping(address => StakePosition) public positions;

    event Staked(address indexed user, uint256 amount, uint256 duration, uint256 weightedAmount);
    event Withdrawn(address indexed user, uint256 amount, uint256 penalty);
    event RewardClaimed(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 newRate);

    constructor(address initialOwner, address _stakingToken, address _rewardToken, uint256 _rewardRate)
        Ownable(initialOwner)
    {
        if (_stakingToken == address(0) || _rewardToken == address(0)) revert ZeroAddress();
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardRatePerSecond = _rewardRate;
        lastUpdateTime = block.timestamp;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            positions[account].accruedRewards = earned(account);
            positions[account].rewardDebt = rewardPerTokenStored;
        }
        _;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalWeightedStake == 0) {
            return rewardPerTokenStored;
        }
        uint256 timePassed = block.timestamp - lastUpdateTime;
        return rewardPerTokenStored + ((timePassed * rewardRatePerSecond * 1e18) / totalWeightedStake);
    }

    function earned(address account) public view returns (uint256) {
        StakePosition memory pos = positions[account];
        return
            ((pos.weightedAmount * (rewardPerToken() - pos.rewardDebt)) / 1e18) +
            pos.accruedRewards;
    }

    function stake(uint256 amount, uint256 lockPeriodSeconds) external nonReentrant whenNotPaused updateReward(_msgSender()) {
        if (amount == 0) revert ZeroAmount();
        StakePosition storage pos = positions[_msgSender()];
        if (pos.principal > 0 && block.timestamp < pos.unlockTime) {
            revert PositionLocked(pos.unlockTime);
        }

        uint256 multiplierBps = 10000; // 1.0x base
        if (lockPeriodSeconds >= 365 days) {
            multiplierBps = 25000; // 2.5x
        } else if (lockPeriodSeconds >= 180 days) {
            multiplierBps = 17500; // 1.75x
        } else if (lockPeriodSeconds >= 90 days) {
            multiplierBps = 13500; // 1.35x
        } else if (lockPeriodSeconds >= 30 days) {
            multiplierBps = 11000; // 1.1x
        }

        uint256 addedWeighted = (amount * multiplierBps) / 10000;

        totalWeightedStake += addedWeighted;
        pos.principal += amount;
        pos.weightedAmount += addedWeighted;
        pos.lockDuration = lockPeriodSeconds;
        pos.startTime = block.timestamp;
        pos.unlockTime = block.timestamp + lockPeriodSeconds;

        bool success = stakingToken.transferFrom(_msgSender(), address(this), amount);
        require(success, "Stake transfer failed");

        emit Staked(_msgSender(), amount, lockPeriodSeconds, addedWeighted);
    }

    function claimReward() public nonReentrant updateReward(_msgSender()) {
        uint256 reward = positions[_msgSender()].accruedRewards;
        if (reward > 0) {
            positions[_msgSender()].accruedRewards = 0;
            bool success = rewardToken.transfer(_msgSender(), reward);
            require(success, "Reward transfer failed");
            emit RewardClaimed(_msgSender(), reward);
        }
    }

    function withdraw(uint256 amount) external nonReentrant updateReward(_msgSender()) {
        StakePosition storage pos = positions[_msgSender()];
        if (amount == 0 || amount > pos.principal) revert InsufficientBalance(pos.principal, amount);

        uint256 penalty = 0;
        if (block.timestamp < pos.unlockTime) {
            // 15% emergency unbonding early penalty fee returned to vault rewards
            penalty = (amount * 1500) / 10000;
        }

        uint256 fraction = (amount * 1e18) / pos.principal;
        uint256 weightedDeduction = (pos.weightedAmount * fraction) / 1e18;
        pos.weightedAmount -= weightedDeduction;
        totalWeightedStake -= weightedDeduction;
        pos.principal -= amount;

        claimReward();

        uint256 returnAmount = amount - penalty;
        bool success = stakingToken.transfer(_msgSender(), returnAmount);
        require(success, "Withdraw transfer failed");

        emit Withdrawn(_msgSender(), returnAmount, penalty);
    }

    function setRewardRate(uint256 newRate) external onlyOwner updateReward(address(0)) {
        rewardRatePerSecond = newRate;
        emit RewardRateUpdated(newRate);
    }
}

// -----------------------------------------------------------------------------
// 4. Automated Market Maker DEX (MagnumSwap Pool with TWAP)
// -----------------------------------------------------------------------------
contract MagnumSwapPool is Context, ReentrancyGuard, IERC20 {
    string public constant name = "Magnum DEX LP Token";
    string public constant symbol = "MOPUS-LP";
    uint8 public constant decimals = 18;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    uint256 public feeNumerator = 30; // 0.30% swap fee
    uint256 public constant FEE_DENOMINATOR = 10000;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
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

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function balanceOf(address ownerAddr) external view override returns (uint256) { return _balances[ownerAddr]; }
    function allowance(address ownerAddr, address spender) external view override returns (uint256) { return _allowances[ownerAddr][spender]; }

    function transfer(address to, uint256 value) external override returns (bool) {
        _transferTokens(_msgSender(), to, value);
        return true;
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        _allowances[_msgSender()][spender] = value;
        emit Approval(_msgSender(), spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        uint256 currentAllowance = _allowances[from][_msgSender()];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) revert InsufficientAllowance(currentAllowance, value);
            _allowances[from][_msgSender()] = currentAllowance - value;
        }
        _transferTokens(from, to, value);
        return true;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "Overflow");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;

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
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external nonReentrant returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        uint256 amount0;
        uint256 amount1;

        if (_reserve0 == 0 && _reserve1 == 0) {
            amount0 = amount0Desired;
            amount1 = amount1Desired;
        } else {
            uint256 amount1Optimal = (amount0Desired * _reserve1) / _reserve0;
            if (amount1Optimal <= amount1Desired) {
                if (amount1Optimal < amount1Min) revert SlippageExceeded();
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = (amount1Desired * _reserve0) / _reserve1;
                assert(amount0Optimal <= amount0Desired);
                if (amount0Optimal < amount0Min) revert SlippageExceeded();
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
            }
        }

        require(token0.transferFrom(_msgSender(), address(this), amount0), "Token0 transfer failed");
        require(token1.transferFrom(_msgSender(), address(this), amount1), "Token1 transfer failed");

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        if (_totalSupply == 0) {
            liquidity = MagnumMath.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mintTokens(address(1), MINIMUM_LIQUIDITY); // lock minimum liquidity forever
        } else {
            liquidity = MagnumMath.min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
        }

        if (liquidity == 0) revert InsufficientLiquidity();
        _mintTokens(to, liquidity);
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Mint(_msgSender(), amount0, amount1);
    }

    function removeLiquidity(
        uint256 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (liquidity == 0) revert ZeroAmount();
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();

        amount0 = (liquidity * _reserve0) / _totalSupply;
        amount1 = (liquidity * _reserve1) / _totalSupply;

        if (amount0 < amount0Min || amount1 < amount1Min) revert SlippageExceeded();

        _burnTokens(_msgSender(), liquidity);

        require(token0.transfer(to, amount0), "Transfer token0 failed");
        require(token1.transfer(to, amount1), "Transfer token1 failed");

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Burn(_msgSender(), amount0, amount1, to);
    }

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to
    ) external nonReentrant {
        if (amount0Out == 0 && amount1Out == 0) revert ZeroAmount();
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        if (amount0Out >= _reserve0 || amount1Out >= _reserve1) revert InsufficientLiquidity();

        if (amount0Out > 0) require(token0.transfer(to, amount0Out), "Token0 transfer failed");
        if (amount1Out > 0) require(token1.transfer(to, amount1Out), "Token1 transfer failed");

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        if (amount0In == 0 && amount1In == 0) revert ZeroAmount();

        {
            uint256 balance0Adjusted = (balance0 * FEE_DENOMINATOR) - (amount0In * feeNumerator);
            uint256 balance1Adjusted = (balance1 * FEE_DENOMINATOR) - (amount1In * feeNumerator);
            require(
                balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * uint256(_reserve1) * (FEE_DENOMINATOR ** 2),
                "K Invariant violation"
            );
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(_msgSender(), amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external view returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - feeNumerator);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _mintTokens(address to, uint256 amount) private {
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burnTokens(address from, uint256 amount) private {
        _balances[from] -= amount;
        _totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function _transferTokens(address from, address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        uint256 senderBal = _balances[from];
        if (senderBal < amount) revert InsufficientBalance(senderBal, amount);
        _balances[from] = senderBal - amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }
}

// -----------------------------------------------------------------------------
// 5. Collateralized Lending & Liquidation Vault (DeFi Nexus Lending)
// -----------------------------------------------------------------------------
contract MagnumLendingVault is Context, Ownable, ReentrancyGuard {
    IERC20 public immutable collateralToken;
    IERC20 public immutable borrowToken;

    uint256 public constant COLLATERAL_FACTOR_BPS = 7500; // 75% LTV (Borrow max 75% of collateral value)
    uint256 public constant LIQUIDATION_THRESHOLD_BPS = 8500; // 85% Liquidation trigger
    uint256 public constant LIQUIDATION_BONUS_BPS = 10500; // 5% Liquidator reward
    uint256 public constant BPS_BASE = 10000;

    // Synthetic price feed oracle representation: collateralPrice / borrowPrice in 1e18 precision
    uint256 public oraclePriceRatio = 2000 * 1e18; // 1 Collateral = 2000 BorrowTokens

    struct AccountState {
        uint256 depositedCollateral;
        uint256 borrowedDebt;
        uint256 lastAccrualTimestamp;
    }

    mapping(address => AccountState) public accounts;
    uint256 public totalDeposits;
    uint256 public totalBorrows;
    uint256 public borrowInterestRatePerYearBps = 800; // 8.00% APR

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(address indexed user, address indexed liquidator, uint256 debtRepaid, uint256 collateralSeized);
    event OraclePriceUpdated(uint256 newPriceRatio);

    constructor(address initialOwner, address _collateralToken, address _borrowToken)
        Ownable(initialOwner)
    {
        if (_collateralToken == address(0) || _borrowToken == address(0)) revert ZeroAddress();
        collateralToken = IERC20(_collateralToken);
        borrowToken = IERC20(_borrowToken);
    }

    function setOraclePriceRatio(uint256 newRatio) external onlyOwner {
        if (newRatio == 0) revert ZeroAmount();
        oraclePriceRatio = newRatio;
        emit OraclePriceUpdated(newRatio);
    }

    function calculateHealthFactor(address user) public view returns (uint256) {
        AccountState memory st = accounts[user];
        if (st.borrowedDebt == 0) return type(uint256).max;

        uint256 collateralVal = (st.depositedCollateral * oraclePriceRatio) / 1e18;
        uint256 thresholdVal = (collateralVal * LIQUIDATION_THRESHOLD_BPS) / BPS_BASE;
        return (thresholdVal * 1e18) / st.borrowedDebt;
    }

    function depositCollateral(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _accrueInterest(_msgSender());

        accounts[_msgSender()].depositedCollateral += amount;
        totalDeposits += amount;

        bool ok = collateralToken.transferFrom(_msgSender(), address(this), amount);
        require(ok, "Collateral transfer failed");

        emit CollateralDeposited(_msgSender(), amount);
    }

    function borrow(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _accrueInterest(_msgSender());

        AccountState storage st = accounts[_msgSender()];
        uint256 collateralVal = (st.depositedCollateral * oraclePriceRatio) / 1e18;
        uint256 maxBorrow = (collateralVal * COLLATERAL_FACTOR_BPS) / BPS_BASE;

        if (st.borrowedDebt + amount > maxBorrow) {
            revert InsufficientLiquidity();
        }

        st.borrowedDebt += amount;
        totalBorrows += amount;

        bool ok = borrowToken.transfer(_msgSender(), amount);
        require(ok, "Borrow transfer failed");

        emit Borrowed(_msgSender(), amount);
    }

    function repay(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _accrueInterest(_msgSender());

        AccountState storage st = accounts[_msgSender()];
        uint256 repayAmount = amount > st.borrowedDebt ? st.borrowedDebt : amount;

        st.borrowedDebt -= repayAmount;
        totalBorrows -= repayAmount;

        bool ok = borrowToken.transferFrom(_msgSender(), address(this), repayAmount);
        require(ok, "Repay transfer failed");

        emit Repaid(_msgSender(), repayAmount);
    }

    function withdrawCollateral(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _accrueInterest(_msgSender());

        AccountState storage st = accounts[_msgSender()];
        if (amount > st.depositedCollateral) revert InsufficientBalance(st.depositedCollateral, amount);

        st.depositedCollateral -= amount;
        if (st.borrowedDebt > 0) {
            uint256 hf = calculateHealthFactor(_msgSender());
            if (hf < 1e18) revert Undercollateralized(hf);
        }
        totalDeposits -= amount;

        bool ok = collateralToken.transfer(_msgSender(), amount);
        require(ok, "Collateral return failed");

        emit CollateralWithdrawn(_msgSender(), amount);
    }

    function liquidate(address borrower, uint256 debtToCover) external nonReentrant {
        if (debtToCover == 0) revert ZeroAmount();
        _accrueInterest(borrower);

        uint256 hf = calculateHealthFactor(borrower);
        if (hf >= 1e18) revert HealthFactorSafe(hf);

        AccountState storage st = accounts[borrower];
        uint256 debt = debtToCover > st.borrowedDebt ? st.borrowedDebt : debtToCover;

        // Required collateral equivalent + liquidation incentive
        uint256 collateralToSeize = (debt * 1e18 * LIQUIDATION_BONUS_BPS) / (oraclePriceRatio * BPS_BASE);
        if (collateralToSeize > st.depositedCollateral) {
            collateralToSeize = st.depositedCollateral;
        }

        st.borrowedDebt -= debt;
        st.depositedCollateral -= collateralToSeize;
        totalBorrows -= debt;
        totalDeposits -= collateralToSeize;

        bool okDebt = borrowToken.transferFrom(_msgSender(), address(this), debt);
        require(okDebt, "Debt transfer failed");

        bool okCollateral = collateralToken.transfer(_msgSender(), collateralToSeize);
        require(okCollateral, "Collateral transfer failed");

        emit Liquidated(borrower, _msgSender(), debt, collateralToSeize);
    }

    function _accrueInterest(address account) internal {
        AccountState storage st = accounts[account];
        if (st.lastAccrualTimestamp == 0) {
            st.lastAccrualTimestamp = block.timestamp;
            return;
        }
        uint256 elapsed = block.timestamp - st.lastAccrualTimestamp;
        if (elapsed > 0 && st.borrowedDebt > 0) {
            uint256 interest = (st.borrowedDebt * borrowInterestRatePerYearBps * elapsed) / (365 days * BPS_BASE);
            st.borrowedDebt += interest;
            totalBorrows += interest;
        }
        st.lastAccrualTimestamp = block.timestamp;
    }
}

// -----------------------------------------------------------------------------
// 6. Decentralized Governance Timelock & Protocol Dispatcher
// -----------------------------------------------------------------------------
contract MagnumGovernance is Context, Ownable {
    uint256 public constant MIN_DELAY = 1 days;
    uint256 public constant MAX_DELAY = 30 days;

    mapping(bytes32 => bool) public queuedTransactions;

    event TransactionQueued(bytes32 indexed txHash, address indexed target, uint256 value, string signature, bytes data, uint256 eta);
    event TransactionExecuted(bytes32 indexed txHash, address indexed target, uint256 value, string signature, bytes data, uint256 eta);
    event TransactionCancelled(bytes32 indexed txHash);

    constructor(address initialAdmin)
        Ownable(initialAdmin)
    {}

    function queueTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external onlyOwner returns (bytes32) {
        if (eta < block.timestamp + MIN_DELAY || eta > block.timestamp + MAX_DELAY) {
            revert("Invalid ETA timestamp");
        }
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = true;

        emit TransactionQueued(txHash, target, value, signature, data, eta);
        return txHash;
    }

    function cancelTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external onlyOwner {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        require(queuedTransactions[txHash], "Transaction not queued");
        queuedTransactions[txHash] = false;

        emit TransactionCancelled(txHash);
    }

    function executeTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external payable onlyOwner returns (bytes memory) {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        require(queuedTransactions[txHash], "Transaction not queued");
        require(block.timestamp >= eta, "Transaction still locked");
        require(block.timestamp <= eta + 14 days, "Transaction expired");

        queuedTransactions[txHash] = false;

        bytes memory callData;
        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        require(success, "Transaction execution reverted");

        emit TransactionExecuted(txHash, target, value, signature, data, eta);
        return returnData;
    }

    receive() external payable {}
}
