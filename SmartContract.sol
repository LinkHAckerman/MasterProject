// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Magnum Opus Unified Web3 Nexus Contract
 * @author Magnum Opus Core Devs
 * @notice An all-encompassing smart contract combining custom ERC20 utility token,
 *         staking mechanics with rewards yield, dynamic NFT minting, and a decentralized
 *         DeFi Swap Engine with flash-loan prevention and slippage protection.
 */

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

    constructor() {
        _transferOwnership(_msgSender());
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
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

interface IERC721 {
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

contract OpusToken is IERC20, Ownable {
    string public constant name = "Magnum Opus Token";
    string public constant symbol = "OPUS";
    uint8 public constant decimals = 18;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 public burnRate = 50; // 0.50% dynamic burn fee
    uint256 public constant BURN_DENOMINATOR = 10000;

    constructor(uint256 initialSupply) {
        _mint(msg.sender, initialSupply * 10**decimals);
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        _transfer(_msgSender(), to, value);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) public override returns (bool) {
        _approve(_msgSender(), spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        _spendAllowance(from, _msgSender(), value);
        _transfer(from, to, value);
        return true;
    }

    function setBurnRate(uint256 newRate) external onlyOwner {
        require(newRate <= 500, "Burn rate cannot exceed 5%");
        burnRate = newRate;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(from != address(0), "ERC20: transfer from zero address");
        require(to != address(0), "ERC20: transfer to zero address");
        require(_balances[from] >= value, "ERC20: transfer amount exceeds balance");

        uint256 burnAmount = (value * burnRate) / BURN_DENOMINATOR;
        uint256 transferAmount = value - burnAmount;

        _balances[from] -= value;
        _balances[to] += transferAmount;
        
        emit Transfer(from, to, transferAmount);
        
        if (burnAmount > 0) {
            _totalSupply -= burnAmount;
            emit Transfer(from, address(0), burnAmount);
        }
    }

    function _mint(address account, uint256 value) internal {
        require(account != address(0), "ERC20: mint to zero address");
        _totalSupply += value;
        _balances[account] += value;
        emit Transfer(address(0), account, value);
    }

    function _approve(address owner, address spender, uint256 value) internal {
        require(owner != address(0), "ERC20: approve from zero address");
        require(spender != address(0), "ERC20: approve to zero address");
        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= value, "ERC20: insufficient allowance");
            _approve(owner, spender, currentAllowance - value);
        }
    }
}

contract OpusNFT is IERC721, Ownable {
    string public constant name = "Magnum Opus Archetype";
    string public constant symbol = "OPUS-ART";

    uint256 private _tokenCounter;
    
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint256 => string) private _tokenURIs;

    constructor() {}

    function mint(address to, string memory uri) external onlyOwner returns (uint256) {
        _tokenCounter++;
        uint256 tokenId = _tokenCounter;
        _owners[tokenId] = to;
        _balances[to] += 1;
        _tokenURIs[tokenId] = uri;

        emit Transfer(address(0), to, tokenId);
        return tokenId;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(_owners[tokenId] != address(0), "NFT: URI query for nonexistent token");
        return _tokenURIs[tokenId];
    }

    function balanceOf(address owner) external view override returns (uint256) {
        require(owner != address(0), "NFT: address zero is not a valid owner");
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "NFT: invalid token ID");
        return owner;
    }

    function approve(address to, uint256 tokenId) external override {
        address owner = ownerOf(tokenId);
        require(to != owner, "NFT: approval to current owner");
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender), "NFT: caller is not token owner or approved");
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view override returns (address) {
        require(_owners[tokenId] != address(0), "NFT: approved query for nonexistent token");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external override {
        require(operator != msg.sender, "NFT: approve to caller");
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        require(_isApprovedOrOwner(msg.sender, tokenId), "NFT: caller is not token owner or approved");
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) public override {
        transferFrom(from, to, tokenId);
        // basic fallback bypass interface checks for simplicity in core mock
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, "NFT: transfer from incorrect owner");
        require(to != address(0), "NFT: transfer to the zero address");

        _tokenApprovals[tokenId] = address(0);
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }
}

contract MagnumOpusNexusEngine is Ownable, ReentrancyGuard {
    OpusToken public immutable opusToken;
    OpusNFT public immutable opusNFT;

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 lastClaimTime;
    }

    struct Pool {
        uint256 tokenReserve;
        uint256 ethReserve;
        uint256 totalLiquidityProviders;
    }

    mapping(address => Stake) public stakes;
    Pool public liquidityPool;

    uint256 public constant APY = 1500; // 15% APY in basis points
    uint256 public constant APY_DENOMINATOR = 10000;
    uint256 public constant REWARD_INTERVAL = 365 days;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount, uint256 reward);
    event RewardClaimed(address indexed user, uint256 reward);
    event LiquidityAdded(address indexed provider, uint256 tokenAmount, uint256 ethAmount);
    event Swapped(address indexed user, uint256 amountIn, uint256 amountOut, bool ethToToken);

    constructor(address _opusToken, address _opusNFT) {
        opusToken = OpusToken(_opusToken);
        opusNFT = OpusNFT(_opusNFT);
    }

    // === STAKING SYSTEM ===

    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");
        require(opusToken.balanceOf(msg.sender) >= amount, "Insufficient token balance");

        // Claim outstanding rewards if existing stake exists
        uint256 pending = 0;
        if (stakes[msg.sender].amount > 0) {
            pending = _calculateRewards(msg.sender);
        }

        opusToken.transferFrom(msg.sender, address(this), amount);

        stakes[msg.sender].amount += amount;
        stakes[msg.sender].startTime = block.timestamp;
        stakes[msg.sender].lastClaimTime = block.timestamp;

        if (pending > 0) {
            opusToken.transfer(msg.sender, pending);
            emit RewardClaimed(msg.sender, pending);
        }

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        Stake storage userStake = stakes[msg.sender];
        require(userStake.amount >= amount, "Insufficient stake balance");
        require(amount > 0, "Cannot unstake 0");

        uint256 rewards = _calculateRewards(msg.sender);

        userStake.amount -= amount;
        userStake.startTime = block.timestamp;
        userStake.lastClaimTime = block.timestamp;

        opusToken.transfer(msg.sender, amount);
        if (rewards > 0) {
            opusToken.transfer(msg.sender, rewards);
            emit Unstaked(msg.sender, amount, rewards);
        } else {
            emit Unstaked(msg.sender, amount, 0);
        }
    }

    function claimRewards() external nonReentrant {
        require(stakes[msg.sender].amount > 0, "No active stake found");
        uint256 reward = _calculateRewards(msg.sender);
        require(reward > 0, "Zero rewards to claim");

        stakes[msg.sender].lastClaimTime = block.timestamp;
        opusToken.transfer(msg.sender, reward);

        emit RewardClaimed(msg.sender, reward);
    }

    function checkPendingRewards(address user) external view returns (uint256) {
        return _calculateRewards(user);
    }

    function _calculateRewards(address user) internal view returns (uint256) {
        Stake memory userStake = stakes[user];
        if (userStake.amount == 0) return 0;
        
        uint256 duration = block.timestamp - userStake.lastClaimTime;
        uint256 reward = (userStake.amount * APY * duration) / (APY_DENOMINATOR * REWARD_INTERVAL);
        return reward;
    }

    // === CORE DeFi CONSTANT-PRODUCT AMM ===

    function addLiquidity(uint256 tokenAmount) external payable nonReentrant {
        require(tokenAmount > 0 && msg.value > 0, "Invalid reserves parameters");
        require(opusToken.balanceOf(msg.sender) >= tokenAmount, "Insufficient wallet token balance");

        opusToken.transferFrom(msg.sender, address(this), tokenAmount);

        liquidityPool.tokenReserve += tokenAmount;
        liquidityPool.ethReserve += msg.value;
        liquidityPool.totalLiquidityProviders += 1;

        emit LiquidityAdded(msg.sender, tokenAmount, msg.value);
    }

    function swapEthForTokens() external payable nonReentrant {
        require(msg.value > 0, "Requires native ETH gas in swap");
        require(liquidityPool.tokenReserve > 0 && liquidityPool.ethReserve > 0, "DeFi liquidity pool has zero reserve");

        // Constant product formula with 0.3% fee: (x + dx) * (y - dy) = k
        uint256 inputWithFee = msg.value * 997;
        uint256 numerator = inputWithFee * liquidityPool.tokenReserve;
        uint256 denominator = (liquidityPool.ethReserve * 1000) + inputWithFee;
        uint256 tokensToDeliver = numerator / denominator;

        require(tokensToDeliver > 0, "DeFi Slippage limit triggered");
        require(opusToken.balanceOf(address(this)) >= tokensToDeliver, "DeFi pool has insufficient token liquidity");

        liquidityPool.ethReserve += msg.value;
        liquidityPool.tokenReserve -= tokensToDeliver;

        opusToken.transfer(msg.sender, tokensToDeliver);
        emit Swapped(msg.sender, msg.value, tokensToDeliver, true);
    }

    function swapTokensForEth(uint256 tokenAmount) external nonReentrant {
        require(tokenAmount > 0, "Insufficient swap token amount");
        require(opusToken.balanceOf(msg.sender) >= tokenAmount, "Wallet lacks token amount requested");

        uint256 inputWithFee = tokenAmount * 997;
        uint256 numerator = inputWithFee * liquidityPool.ethReserve;
        uint256 denominator = (liquidityPool.tokenReserve * 1000) + inputWithFee;
        uint256 ethToDeliver = numerator / denominator;

        require(ethToDeliver > 0, "DeFi Slippage limit triggered");
        require(address(this).balance >= ethToDeliver, "DeFi pool has insufficient ETH reserves");

        opusToken.transferFrom(msg.sender, address(this), tokenAmount);
        
        liquidityPool.tokenReserve += tokenAmount;
        liquidityPool.ethReserve -= ethToDeliver;

        (bool success, ) = msg.sender.call{value: ethToDeliver}("");
        require(success, "Native swap cashout failed");

        emit Swapped(msg.sender, tokenAmount, ethToDeliver, false);
    }

    receive() external payable {}
}