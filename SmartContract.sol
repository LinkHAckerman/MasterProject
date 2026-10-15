// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MagnumOpusDeFiEngine
 * @notice The Ultimate Web3, DeFi, Staking, DEX, and NFT Core Architecture.
 * Part of the MAGNUM OPUS Platform.
 */

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

contract MagnumOpusToken is IERC20 {
    string public name = "Magnum Opus Protocol";
    string public symbol = "MOPUS";
    uint8 public decimals = 18;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "MagnumOpusToken: caller is not the owner");
        _;
    }

    constructor(uint256 initialSupply) {
        owner = msg.sender;
        _mint(msg.sender, initialSupply * (10 ** uint256(decimals)));
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address ownerAddress, address spender) external view override returns (uint256) {
        return _allowances[ownerAddress][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, msg.sender, currentAllowance - amount);
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

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from zero address");
        require(recipient != address(0), "ERC20: transfer to zero address");

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to zero address");

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from zero address");

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    function _approve(address ownerAddress, address spender, uint256 amount) internal {
        require(ownerAddress != address(0), "ERC20: approve from zero address");
        require(spender != address(0), "ERC20: approve to zero address");

        _allowances[ownerAddress][spender] = amount;
        emit Approval(ownerAddress, spender, amount);
    }
}

/**
 * @title MagnumOpusStakingVault
 * @notice Simple ERC20 staking vault that distributes reward tokens proportionally to stake.
 */
contract MagnumOpusStakingVault {
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    address public owner;
    uint256 public rewardRate; // reward tokens per second
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public totalStaked;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public userRewards;
    mapping(address => uint256) public userStakes;

    modifier onlyOwner() {
        require(msg.sender == owner, "MagnumOpusStakingVault: caller is not the owner");
        _;
    }

    constructor(address _stakingToken, address _rewardToken) {
        owner = msg.sender;
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
    }

    function stake(uint256 amount) external {
        require(amount > 0, "MagnumOpusStakingVault: cannot stake 0");
        require(stakingToken.transferFrom(msg.sender, address(this), amount), "MagnumOpusStakingVault: transfer failed");

        _updateReward(msg.sender);
        userStakes[msg.sender] += amount;
        totalStaked += amount;
    }

    function unstake(uint256 amount) external {
        require(amount > 0, "MagnumOpusStakingVault: cannot unstake 0");
        require(userStakes[msg.sender] >= amount, "MagnumOpusStakingVault: insufficient stake");

        _updateReward(msg.sender);
        userStakes[msg.sender] -= amount;
        totalStaked -= amount;
        require(stakingToken.transfer(msg.sender, amount), "MagnumOpusStakingVault: transfer failed");
    }

    function claimRewards() external {
        _updateReward(msg.sender);
        uint256 reward = userRewards[msg.sender];
        if (reward > 0) {
            userRewards[msg.sender] = 0;
            require(rewardToken.transfer(msg.sender, reward), "MagnumOpusStakingVault: transfer failed");
        }
    }

    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        _updateReward(address(0));
        rewardRate = _rewardRate;
    }

    function _updateReward(address account) internal {
        if (account != address(0)) {
            userRewards[account] += (totalStaked * (rewardPerTokenStored - userRewardPerTokenPaid[account])) / 1e18;
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }

        uint256 currentTime = block.timestamp;
        uint256 timeElapsed = currentTime - lastUpdateTime;
        if (timeElapsed > 0 && totalStaked > 0) {
            rewardPerTokenStored += (timeElapsed * rewardRate * 1e18) / totalStaked;
        }
        lastUpdateTime = currentTime;
    }
}

/**
 * @title MagnumOpusNFT
 * @notice Non-Fungible Token (NFT) contract with basic minting and transfer functionality.
 */
contract MagnumOpusNFT {
    string public name = "Magnum Opus NFT";
    string public symbol = "MONFT";

    address public owner;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => bool) private _exists;

    uint256 private _totalSupply;

    modifier onlyOwner() {
        require(msg.sender == owner, "MagnumOpusNFT: caller is not the owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        require(_exists[tokenId], "MagnumOpusNFT: token does not exist");
        return _owners[tokenId];
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        require(_exists[tokenId], "MagnumOpusNFT: token does not exist");
        require(_owners[tokenId] == from, "MagnumOpusNFT: transfer from incorrect owner");
        require(to != address(0), "MagnumOpusNFT: transfer to zero address");

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function mint(address to, uint256 tokenId) external onlyOwner {
        require(to != address(0), "MagnumOpusNFT: mint to zero address");
        require(!_exists[tokenId], "MagnumOpusNFT: token already exists");

        _balances[to] += 1;
        _owners[tokenId] = to;
        _exists[tokenId] = true;
        _totalSupply += 1;

        emit Transfer(address(0), to, tokenId);
    }

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
}

/**
 * @title MagnumOpusDEX
 * @notice Decentralized Exchange (DEX) contract for trading ERC20 tokens.
 */
contract MagnumOpusDEX {
    struct Order {
        address trader;
        uint256 amount;
        uint256 price;
        bool isBuy;
    }

    IERC20 public tokenA;
    IERC20 public tokenB;

    address public owner;

    mapping(uint256 => Order) public orders;
    uint256 public orderCount;

    modifier onlyOwner() {
        require(msg.sender == owner, "MagnumOpusDEX: caller is not the owner");
        _;
    }

    constructor(address _tokenA, address _tokenB) {
        owner = msg.sender;
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    function createOrder(uint256 amount, uint256 price, bool isBuy) external {
        require(amount > 0, "MagnumOpusDEX: amount must be greater than 0");
        require(price > 0, "MagnumOpusDEX: price must be greater than 0");

        if (isBuy) {
            require(tokenB.transferFrom(msg.sender, address(this), amount * price), "MagnumOpusDEX: transfer failed");
        } else {
            require(tokenA.transferFrom(msg.sender, address(this), amount), "MagnumOpusDEX: transfer failed");
        }

        orderCount += 1;
        orders[orderCount] = Order(msg.sender, amount, price, isBuy);

        emit OrderCreated(orderCount, msg.sender, amount, price, isBuy);
    }

    function matchOrder(uint256 orderId) external {
        require(orders[orderId].trader != address(0), "MagnumOpusDEX: order does not exist");
        require(orders[orderId].trader != msg.sender, "MagnumOpusDEX: cannot match own order");

        Order memory order = orders[orderId];
        uint256 amount = order.amount;
        uint256 price = order.price;
        bool isBuy = order.isBuy;

        if (isBuy) {
            require(tokenA.transferFrom(msg.sender, address(this), amount), "MagnumOpusDEX: transfer failed");
            require(tokenB.transfer(order.trader, amount * price), "MagnumOpusDEX: transfer failed");
            require(tokenA.transfer(msg.sender, amount), "MagnumOpusDEX: transfer failed");
        } else {
            require(tokenB.transferFrom(msg.sender, address(this), amount * price), "MagnumOpusDEX: transfer failed");
            require(tokenA.transfer(order.trader, amount), "MagnumOpusDEX: transfer failed");
            require(tokenB.transfer(msg.sender, amount * price), "MagnumOpusDEX: transfer failed");
        }

        delete orders[orderId];

        emit OrderMatched(orderId, msg.sender, amount, price, isBuy);
    }

    event OrderCreated(uint256 indexed orderId, address indexed trader, uint256 amount, uint256 price, bool isBuy);
    event OrderMatched(uint256 indexed orderId, address indexed trader, uint256 amount, uint256 price, bool isBuy);
}