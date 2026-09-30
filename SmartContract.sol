// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Magnum Opus Unified Web3 & DeFi Protocol
 * @author Magnum Opus Architecture Team
 * @notice Complete multi-ecosystem DeFi, Token, NFT, and Liquidity Vault System
 */

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
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool _approved) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

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

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is zero address");
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

contract MagnumOpusToken is Context, IERC20, Ownable {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private constant _decimals = 18;

    uint256 public burnFeeBps = 100; // 1%
    uint256 public treasuryFeeBps = 100; // 1%
    address public treasuryAddress;

    mapping(address => bool) public isExcludedFromFees;

    event FeesUpdated(uint256 burnFeeBps, uint256 treasuryFeeBps);
    event TreasuryUpdated(address indexed newTreasury);

    constructor(string memory name_, string memory symbol_, address treasury_) {
        _name = name_;
        _symbol = symbol_;
        treasuryAddress = treasury_;
        isExcludedFromFees[msg.sender] = true;
        isExcludedFromFees[treasury_] = true;
        _mint(msg.sender, 100_000_000 * 10**_decimals);
    }

    function name() public view returns (string memory) { return _name; }
    function symbol() public view returns (string memory) { return _symbol; }
    function decimals() public pure returns (uint8) { return _decimals; }
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
        _spendAllowance(from, _msgSender(), amount);
        _transfer(from, to, amount);
        return true;
    }

    function setFees(uint256 _burnFeeBps, uint256 _treasuryFeeBps) external onlyOwner {
        require(_burnFeeBps + _treasuryFeeBps <= 1000, "Fees exceed 10%");
        burnFeeBps = _burnFeeBps;
        treasuryFeeBps = _treasuryFeeBps;
        emit FeesUpdated(_burnFeeBps, _treasuryFeeBps);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury address");
        treasuryAddress = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function setExcludedFromFees(address account, bool excluded) external onlyOwner {
        isExcludedFromFees[account] = excluded;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        require(_balances[from] >= amount, "Exceeds balance");

        uint256 burnAmount = 0;
        uint256 treasuryAmount = 0;

        if (!isExcludedFromFees[from] && !isExcludedFromFees[to]) {
            burnAmount = (amount * burnFeeBps) / 10000;
            treasuryAmount = (amount * treasuryFeeBps) / 10000;
        }

        uint256 sendAmount = amount - burnAmount - treasuryAmount;

        _balances[from] -= amount;
        _balances[to] += sendAmount;
        emit Transfer(from, to, sendAmount);

        if (burnAmount > 0) {
            _totalSupply -= burnAmount;
            emit Transfer(from, address(0), burnAmount);
        }

        if (treasuryAmount > 0) {
            _balances[treasuryAddress] += treasuryAmount;
            emit Transfer(from, treasuryAddress, treasuryAmount);
        }
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "Mint to zero address");
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "Approve from zero");
        require(spender != address(0), "Approve to zero");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "Insufficient allowance");
            _approve(owner, spender, currentAllowance - amount);
        }
    }
}

contract MagnumOpusVault is Ownable, ReentrancyGuard {
    struct StakingPosition {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lockEndTime;
    }

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    uint256 public rewardRatePerSecond;
    uint256 public lastUpdateTime;
    uint256 public accRewardPerShare;
    uint256 public totalStaked;

    mapping(address => StakingPosition) public positions;

    event Staked(address indexed user, uint256 amount, uint256 lockPeriod);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);

    constructor(address _stakingToken, address _rewardToken, uint256 _rewardRate) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardRatePerSecond = _rewardRate;
        lastUpdateTime = block.timestamp;
    }

    function updatePool() public {
        if (block.timestamp <= lastUpdateTime) return;
        if (totalStaked == 0) {
            lastUpdateTime = block.timestamp;
            return;
        }

        uint256 elapsed = block.timestamp - lastUpdateTime;
        uint256 reward = elapsed * rewardRatePerSecond;
        accRewardPerShare += (reward * 1e12) / totalStaked;
        lastUpdateTime = block.timestamp;
    }

    function pendingReward(address user) public view returns (uint256) {
        StakingPosition memory pos = positions[user];
        uint256 _accRewardPerShare = accRewardPerShare;

        if (block.timestamp > lastUpdateTime && totalStaked != 0) {
            uint256 elapsed = block.timestamp - lastUpdateTime;
            uint256 reward = elapsed * rewardRatePerSecond;
            _accRewardPerShare += (reward * 1e12) / totalStaked;
        }

        return ((pos.amount * _accRewardPerShare) / 1e12) - pos.rewardDebt;
    }

    function stake(uint256 amount, uint256 lockDurationSeconds) external nonReentrant {
        require(amount > 0, "Cannot stake 0");
        updatePool();

        StakingPosition storage pos = positions[msg.sender];
        if (pos.amount > 0) {
            uint256 pending = ((pos.amount * accRewardPerShare) / 1e12) - pos.rewardDebt;
            if (pending > 0) {
                rewardToken.transfer(msg.sender, pending);
                emit RewardClaimed(msg.sender, pending);
            }
        }

        stakingToken.transferFrom(msg.sender, address(this), amount);
        pos.amount += amount;
        pos.lockEndTime = block.timestamp + lockDurationSeconds;
        totalStaked += amount;
        pos.rewardDebt = (pos.amount * accRewardPerShare) / 1e12;

        emit Staked(msg.sender, amount, lockDurationSeconds);
    }

    function unstake(uint256 amount) external nonReentrant {
        StakingPosition storage pos = positions[msg.sender];
        require(pos.amount >= amount, "Exceeds stake");
        require(block.timestamp >= pos.lockEndTime, "Stake still locked");

        updatePool();

        uint256 pending = ((pos.amount * accRewardPerShare) / 1e12) - pos.rewardDebt;
        pos.amount -= amount;
        totalStaked -= amount;
        pos.rewardDebt = (pos.amount * accRewardPerShare) / 1e12;

        stakingToken.transfer(msg.sender, amount);
        if (pending > 0) {
            rewardToken.transfer(msg.sender, pending);
            emit RewardClaimed(msg.sender, pending);
        }

        emit Unstaked(msg.sender, amount);
    }

    function claim() external nonReentrant {
        updatePool();
        StakingPosition storage pos = positions[msg.sender];
        uint256 pending = ((pos.amount * accRewardPerShare) / 1e12) - pos.rewardDebt;
        require(pending > 0, "No rewards to claim");

        pos.rewardDebt = (pos.amount * accRewardPerShare) / 1e12;
        rewardToken.transfer(msg.sender, pending);
        emit RewardClaimed(msg.sender, pending);
    }
}