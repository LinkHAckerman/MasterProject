// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MAGNUM OPUS // Universal Web3, DeFi, and NFT Protocol Engine
 * @author Magnum Opus Core Architecture Team
 * @notice Comprehensive decentralized suite featuring:
 *  1. NexusToken (ERC20) with EIP-2612 gasless permits and deflationary burn logic.
 *  2. NexusArtifactNFT (ERC721 & EIP-2981) dynamic utility NFT with traits & royalty standard.
 *  3. NexusAMM Automated Market Maker / Liquidity Pool engine with fee routing.
 *  4. NexusVault DeFi Staking & Yield Optimizer with tiered lockup multipliers.
 */

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
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
    function setApprovalForAll(address operator, bool approved) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

interface IERC2981 {
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount);
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

abstract contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        require(initialOwner != address(0), "Ownable: zero address");
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not owner");
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/**
 * @dev Nexus Governance and Utility Token (NOPS)
 */
contract NexusToken is IERC20, Ownable {
    string public name = "Magnum Opus Nexus";
    string public symbol = "NOPS";
    uint8 public decimals = 18;
    uint256 private _totalSupply;
    uint256 public constant MAX_SUPPLY = 100_000_000 * 10**18;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) public nonces;

    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    event Burn(address indexed burner, uint256 amount);

    constructor(address initialOwner) Ownable(initialOwner) {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
        _mint(initialOwner, 20_000_000 * 10**18);
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), to, amount);
        return true;
    }

    function allowance(address ownerAddr, address spender) public view override returns (uint256) {
        return _allowances[ownerAddr][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _spendAllowance(from, _msgSender(), amount);
        _transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        require(_totalSupply + amount <= MAX_SUPPLY, "Cap exceeded");
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(_msgSender(), amount);
    }

    function permit(
        address ownerAddr,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(block.timestamp <= deadline, "Permit expired");
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, ownerAddr, spender, value, nonces[ownerAddr]++, deadline)
        );
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signer = ecrecover(hash, v, r, s);
        require(signer != address(0) && signer == ownerAddr, "Invalid permit signature");
        _approve(ownerAddr, spender, value);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "Transfer from zero");
        require(to != address(0), "Transfer to zero");
        require(_balances[from] >= amount, "Insufficient balance");
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "Mint to zero");
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "Burn from zero");
        require(_balances[account] >= amount, "Insufficient balance to burn");
        _balances[account] -= amount;
        _totalSupply -= amount;
        emit Burn(account, amount);
        emit Transfer(account, address(0), amount);
    }

    function _approve(address ownerAddr, address spender, uint256 amount) internal {
        require(ownerAddr != address(0), "Approve from zero");
        require(spender != address(0), "Approve to zero");
        _allowances[ownerAddr][spender] = amount;
        emit Approval(ownerAddr, spender, amount);
    }

    function _spendAllowance(address ownerAddr, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowance(ownerAddr, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "Insufficient allowance");
            _approve(ownerAddr, spender, currentAllowance - amount);
        }
    }
}

/**
 * @dev Nexus Artifact NFT with dynamic rarity, level progression, and on-chain royalty
 */
contract NexusArtifactNFT is IERC721, IERC2981, Ownable {
    string public name = "Nexus Cyber Artifacts";
    string public symbol = "NARTI";
    
    uint256 public nextTokenId = 1;
    uint256 public mintPrice = 0.05 ether;
    address public royaltyReceiver;
    uint96 public royaltyFeeBps = 500; // 5.0%

    struct ArtifactMeta {
        uint8 tier; // 1: Common, 2: Rare, 3: Mythic, 4: Singularity
        uint16 level;
        uint32 powerPoints;
        uint64 forgedTimestamp;
    }

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint256 => ArtifactMeta) public artifactData;

    event ArtifactMinted(address indexed minter, uint256 indexed tokenId, uint8 tier);
    event ArtifactUpgraded(uint256 indexed tokenId, uint16 newLevel, uint32 newPower);

    constructor(address initialOwner) Ownable(initialOwner) {
        royaltyReceiver = initialOwner;
    }

    function royaltyInfo(uint256, uint256 salePrice) external view override returns (address, uint256) {
        uint256 royaltyAmount = (salePrice * royaltyFeeBps) / 10000;
        return (royaltyReceiver, royaltyAmount);
    }

    function setRoyaltyInfo(address receiver, uint96 feeBps) external onlyOwner {
        require(feeBps <= 1500, "Royalty max 15%");
        royaltyReceiver = receiver;
        royaltyFeeBps = feeBps;
    }

    function mintArtifact() external payable returns (uint256) {
        require(msg.value >= mintPrice, "Underpriced");
        uint256 tokenId = nextTokenId++;
        
        uint8 tier = 1;
        bytes32 rand = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender, tokenId));
        uint256 roll = uint256(rand) % 100;
        if (roll >= 98) tier = 4;
        else if (roll >= 85) tier = 3;
        else if (roll >= 60) tier = 2;

        _mint(msg.sender, tokenId);
        artifactData[tokenId] = ArtifactMeta({
            tier: tier,
            level: 1,
            powerPoints: uint32(tier * 250),
            forgedTimestamp: uint64(block.timestamp)
        });

        emit ArtifactMinted(msg.sender, tokenId, tier);
        return tokenId;
    }

    function upgradeArtifact(uint256 tokenId) external payable {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        require(msg.value >= 0.01 ether, "Upgrade fee required");
        
        ArtifactMeta storage meta = artifactData[tokenId];
        meta.level += 1;
        meta.powerPoints += uint32(meta.tier * 75);

        emit ArtifactUpgraded(tokenId, meta.level, meta.powerPoints);
    }

    function withdrawEth(address to) external onlyOwner {
        payable(to).transfer(address(this).balance);
    }

    function balanceOf(address ownerAddr) public view override returns (uint256) {
        require(ownerAddr != address(0), "Zero address query");
        return _balances[ownerAddr];
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        address tokenOwner = _owners[tokenId];
        require(tokenOwner != address(0), "Token does not exist");
        return tokenOwner;
    }

    function approve(address to, uint256 tokenId) public override {
        address tokenOwner = ownerOf(tokenId);
        require(to != tokenOwner, "Approval to current owner");
        require(_msgSender() == tokenOwner || isApprovedForAll(tokenOwner, _msgSender()), "Unauthorized");
        _tokenApprovals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view override returns (address) {
        require(_owners[tokenId] != address(0), "Nonexistent token");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public override {
        require(operator != _msgSender(), "Approve to caller");
        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    function isApprovedForAll(address ownerAddr, address operator) public view override returns (bool) {
        return _operatorApprovals[ownerAddr][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "Not approved nor owner");
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override {
        transferFrom(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address tokenOwner = ownerOf(tokenId);
        return (spender == tokenOwner || isApprovedForAll(tokenOwner, spender) || getApproved(tokenId) == spender);
    }

    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0), "Mint to zero");
        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, "Incorrect owner");
        require(to != address(0), "Transfer to zero");

        delete _tokenApprovals[tokenId];
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }
}

/**
 * @dev Constant-Product Automated Market Maker (AMM) Liquidity Pool Engine
 */
contract NexusAMM is ReentrancyGuard, Ownable {
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public reserve0;
    uint256 public reserve1;
    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidityBalances;

    event MintLiquidity(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidityMinted);
    event BurnLiquidity(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidityBurned);
    event Swap(address indexed sender, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);

    constructor(address _token0, address _token1, address _owner) Ownable(_owner) {
        require(_token0 != _token1, "Identical tokens");
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    function addLiquidity(uint256 amount0Desired, uint256 amount1Desired) external nonReentrant returns (uint256 liquidity) {
        require(amount0Desired > 0 && amount1Desired > 0, "Zero amounts");
        token0.transferFrom(msg.sender, address(this), amount0Desired);
        token1.transferFrom(msg.sender, address(this), amount1Desired);

        if (totalLiquidity == 0) {
            liquidity = _sqrt(amount0Desired * amount1Desired);
        } else {
            uint256 l0 = (amount0Desired * totalLiquidity) / reserve0;
            uint256 l1 = (amount1Desired * totalLiquidity) / reserve1;
            liquidity = l0 < l1 ? l0 : l1;
        }

        require(liquidity > 0, "Insufficient liquidity minted");
        liquidityBalances[msg.sender] += liquidity;
        totalLiquidity += liquidity;

        reserve0 = token0.balanceOf(address(this));
        reserve1 = token1.balanceOf(address(this));

        emit MintLiquidity(msg.sender, amount0Desired, amount1Desired, liquidity);
    }

    function removeLiquidity(uint256 liquidity) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        require(liquidity > 0 && liquidityBalances[msg.sender] >= liquidity, "Invalid liquidity");

        amount0 = (liquidity * reserve0) / totalLiquidity;
        amount1 = (liquidity * reserve1) / totalLiquidity;
        require(amount0 > 0 && amount1 > 0, "Zero withdraw amounts");

        liquidityBalances[msg.sender] -= liquidity;
        totalLiquidity -= liquidity;

        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);

        reserve0 = token0.balanceOf(address(this));
        reserve1 = token1.balanceOf(address(this));

        emit BurnLiquidity(msg.sender, amount0, amount1, liquidity);
    }

    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut) external nonReentrant returns (uint256 amountOut) {
        require(tokenIn == address(token0) || tokenIn == address(token1), "Invalid tokenIn");
        require(amountIn > 0, "Zero input");

        bool isToken0 = tokenIn == address(token0);
        IERC20 inputToken = isToken0 ? token0 : token1;
        IERC20 outputToken = isToken0 ? token1 : token0;

        uint256 resIn = isToken0 ? reserve0 : reserve1;
        uint256 resOut = isToken0 ? reserve1 : reserve0;

        inputToken.transferFrom(msg.sender, address(this), amountIn);
        
        // 0.3% protocol trading fee (997/1000 multiplier)
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * resOut;
        uint256 denominator = (resIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;

        require(amountOut >= minAmountOut, "Slippage exceeded");
        outputToken.transfer(msg.sender, amountOut);

        reserve0 = token0.balanceOf(address(this));
        reserve1 = token1.balanceOf(address(this));

        emit Swap(msg.sender, tokenIn, amountIn, address(outputToken), amountOut);
    }

    function getEstimatedOutput(address tokenIn, uint256 amountIn) external view returns (uint256) {
        if (amountIn == 0 || reserve0 == 0 || reserve1 == 0) return 0;
        bool isToken0 = tokenIn == address(token0);
        uint256 resIn = isToken0 ? reserve0 : reserve1;
        uint256 resOut = isToken0 ? reserve1 : reserve0;

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * resOut;
        uint256 denominator = (resIn * 1000) + amountInWithFee;
        return numerator / denominator;
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

/**
 * @dev Staking & Yield Vault Engine with lock periods and reward distribution
 */
contract NexusVault is ReentrancyGuard, Ownable {
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    uint256 public rewardRatePerSecond = 100000000000000; // Micro rewards per sec
    uint256 public totalStaked;

    struct StakeInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint64 lockExpiry;
        uint16 lockMultiplierBps; // 10000 = 1.0x, 15000 = 1.5x, etc.
    }

    mapping(address => StakeInfo) public stakes;

    event Staked(address indexed user, uint256 amount, uint64 lockExpiry);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);

    constructor(address _stakingToken, address _rewardToken, address _owner) Ownable(_owner) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
    }

    function stake(uint256 amount, uint32 lockDurationDays) external nonReentrant {
        require(amount > 0, "Zero stake");
        updateReward(msg.sender);

        stakingToken.transferFrom(msg.sender, address(this), amount);

        uint16 multiplierBps = 10000;
        if (lockDurationDays >= 180) {
            multiplierBps = 20000; // 2x
        } else if (lockDurationDays >= 90) {
            multiplierBps = 15000; // 1.5x
        } else if (lockDurationDays >= 30) {
            multiplierBps = 12000; // 1.2x
        }

        StakeInfo storage user = stakes[msg.sender];
        user.amount += amount;
        user.lockExpiry = uint64(block.timestamp + (uint256(lockDurationDays) * 1 days));
        user.lockMultiplierBps = multiplierBps;
        totalStaked += amount;

        emit Staked(msg.sender, amount, user.lockExpiry);
    }

    function withdraw(uint256 amount) external nonReentrant {
        StakeInfo storage user = stakes[msg.sender];
        require(user.amount >= amount, "Withdraw exceeds balance");
        require(block.timestamp >= user.lockExpiry, "Tokens locked");

        updateReward(msg.sender);

        user.amount -= amount;
        totalStaked -= amount;
        stakingToken.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function claimReward() external nonReentrant {
        updateReward(msg.sender);
        StakeInfo storage user = stakes[msg.sender];
        uint256 pending = user.rewardDebt;
        require(pending > 0, "No pending rewards");

        user.rewardDebt = 0;
        rewardToken.transfer(msg.sender, pending);

        emit RewardClaimed(msg.sender, pending);
    }

    function updateReward(address account) internal {
        StakeInfo storage user = stakes[account];
        if (user.amount > 0) {
            uint256 pending = (user.amount * rewardRatePerSecond * user.lockMultiplierBps) / (10000 * 10**18);
            user.rewardDebt += pending;
        }
    }

    function setRewardRate(uint256 newRate) external onlyOwner {
        rewardRatePerSecond = newRate;
    }

    function emergencyDrainReward(address to, uint256 amount) external onlyOwner {
        rewardToken.transfer(to, amount);
    }
}
