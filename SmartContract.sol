// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MAGNUM OPUS // Web3 & DeFi Nexus Engine Smart Contract
 * @author Lead Principal Software Architect & AI Colleagues
 * @notice An all-in-one, ultra-optimized, high-performance DeFi liquidity engine,
 *         automated market maker (AMM), yield-farming engine, and NFT-backed boost registry.
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
    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
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

contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract NexusToken is IERC20, Ownable {
    string public constant name = "Magnum Nexus Token";
    string public constant symbol = "NEXUS";
    uint8 public constant decimals = 18;
    
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    address public minter;

    modifier onlyMinter() {
        require(msg.sender == minter || msg.sender == owner(), "NexusToken: caller is not authorized to mint");
        _;
    }

    constructor() {
        minter = msg.sender;
        _mint(msg.sender, 1_000_000 * 10**decimals);
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value);
        return true;
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyMinter {
        _burn(from, amount);
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(from != address(0), "ERC20: transfer from zero address");
        require(to != address(0), "ERC20: transfer to zero address");
        require(_balances[from] >= value, "ERC20: transfer amount exceeds balance");

        _balances[from] -= value;
        _balances[to] += value;
        emit Transfer(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value) internal {
        require(owner != address(0), "ERC20: approve from zero address");
        require(spender != address(0), "ERC20: approve to zero address");

        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= value, "ERC20: insufficient allowance");
            _approve(owner, spender, currentAllowance - value);
        }
    }

    function _mint(address account, uint256 value) internal {
        require(account != address(0), "ERC20: mint to zero address");
        _totalSupply += value;
        _balances[account] += value;
        emit Transfer(address(0), account, value);
    }

    function _burn(address account, uint256 value) internal {
        require(account != address(0), "ERC20: burn from zero address");
        require(_balances[account] >= value, "ERC20: burn amount exceeds balance");

        _balances[account] -= value;
        _totalSupply -= value;
        emit Transfer(account, address(0), value);
    }
}

contract MagnumDeFiEngine is ReentrancyGuard, Ownable {
    IERC20 public tokenA;
    IERC20 public tokenB;
    NexusToken public rewardToken;
    IERC721 public nftMembership;

    uint256 public reserveA;
    uint256 public reserveB;
    uint256 public totalLPShares;
    mapping(address => uint256) public lpShares;

    struct StakerInfo {
        uint256 stakedLP;
        uint256 rewardDebt;
        uint256 lastStakedTimestamp;
        uint256 lockedUntil;
    }

    mapping(address => StakerInfo) public stakers;
    uint256 public accRewardsPerShare;
    uint256 public lastRewardBlock;
    uint256 public totalStakedLP;
    uint256 public constant REWARDS_PER_BLOCK = 1 * 10**18;
    uint256 public constant PRECISION = 1e12;

    uint256 public constant SWAP_FEE_BPS = 30;
    uint256 public constant NFT_BOOST_PERCENT = 20;

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpSharesMinted);
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpSharesBurned);
    event Swapped(address indexed user, address indexed tokenIn, uint256 amountIn, address indexed tokenOut, uint256 amountOut);
    event Staked(address indexed user, uint256 amount, uint256 lockDuration);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event ConfigUpdated(address indexed nftContract);

    constructor(address _tokenA, address _tokenB, address _nft) {
        require(_tokenA != address(0) && _tokenB != address(0), "Invalid tokens");
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        nftMembership = IERC721(_nft);
        rewardToken = new NexusToken();
        lastRewardBlock = block.number;
    }

    function addLiquidity(uint256 amountADesired, uint256 amountBDesired) external nonReentrant returns (uint256 shares) {
        require(tokenA.transferFrom(msg.sender, address(this), amountADesired), "TransferA failed");
        require(tokenB.transferFrom(msg.sender, address(this), amountBDesired), "TransferB failed");

        uint256 _reserveA = reserveA;
        uint256 _reserveB = reserveB;

        if (_reserveA == 0 && _reserveB == 0) {
            shares = sqrt(amountADesired * amountBDesired);
            require(shares > 1000, "Insignificant liquidity");
        } else {
            uint256 optimalB = (amountADesired * _reserveB) / _reserveA;
            if (optimalB <= amountBDesired) {
                shares = (amountADesired * totalLPShares) / _reserveA;
                uint256 excessB = amountBDesired - optimalB;
                if (excessB > 0) {
                    require(tokenB.transfer(msg.sender, excessB), "RefundB failed");
                }
            } else {
                uint256 optimalA = (amountBDesired * _reserveA) / _reserveB;
                require(optimalA <= amountADesired, "Ratio mismatch");
                shares = (amountBDesired * totalLPShares) / _reserveB;
                uint256 excessA = amountADesired - optimalA;
                if (excessA > 0) {
                    require(tokenA.transfer(msg.sender, excessA), "RefundA failed");
                }
            }
        }

        require(shares > 0, "Shares must be > 0");
        lpShares[msg.sender] += shares;
        totalLPShares += shares;

        reserveA = tokenA.balanceOf(address(this));
        reserveB = tokenB.balanceOf(address(this));

        emit LiquidityAdded(msg.sender, amountADesired, amountBDesired, shares);
    }

    function removeLiquidity(uint256 shares) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        require(lpShares[msg.sender] >= shares, "Insufficient shares");
        
        uint256 _totalLPShares = totalLPShares;
        amountA = (shares * reserveA) / _totalLPShares;
        amountB = (shares * reserveB) / _totalLPShares;

        require(amountA > 0 && amountB > 0, "Redeemed amounts too low");

        lpShares[msg.sender] -= shares;
        totalLPShares -= shares;

        reserveA -= amountA;
        reserveB -= amountB;

        require(tokenA.transfer(msg.sender, amountA), "RedeemA failed");
        require(tokenB.transfer(msg.sender, amountB), "RedeemB failed");

        emit LiquidityRemoved(msg.sender, amountA, amountB, shares);
    }

    function swap(address tokenIn, uint256 amountIn) external nonReentrant returns (uint256 amountOut) {
        require(tokenIn == address(tokenA) || tokenIn == address(tokenB), "Invalid input token");
        require(amountIn > 0, "Input must be > 0");

        bool isA = tokenIn == address(tokenA);
        IERC20 sourceToken = isA ? tokenA : tokenB;
        IERC20 targetToken = isA ? tokenB : tokenA;
        uint256 rIn = isA ? reserveA : reserveB;
        uint256 rOut = isA ? reserveB : reserveA;

        require(sourceToken.transferFrom(msg.sender, address(this), amountIn), "TransferIn failed");

        uint256 amountInWithFee = amountIn * (10000 - SWAP_FEE_BPS);
        uint256 numerator = amountInWithFee * rOut;
        uint256 denominator = (rIn * 10000) + amountInWithFee;
        amountOut = numerator / denominator;

        require(amountOut > 0 && amountOut < rOut, "Insufficent output liquidity");

        require(targetToken.transfer(msg.sender, amountOut), "TransferOut failed");

        reserveA = tokenA.balanceOf(address(this));
        reserveB = tokenB.balanceOf(address(this));

        emit Swapped(msg.sender, tokenIn, amountIn, address(targetToken), amountOut);
    }

    function updatePool() public {
        if (block.number <= lastRewardBlock) return;
        if (totalStakedLP == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = block.number - lastRewardBlock;
        uint256 nexusReward = multiplier * REWARDS_PER_BLOCK;
        
        rewardToken.mint(address(this), nexusReward);

        accRewardsPerShare += (nexusReward * PRECISION) / totalStakedLP;
        lastRewardBlock = block.number;
    }

    function stakeLP(uint256 amount, uint256 lockDuration) external nonReentrant {
        require(amount > 0, "Cannot stake 0");
        require(lpShares[msg.sender] >= amount, "Insufficient LP shares to stake");
        require(lockDuration <= 365 days, "Lock duration exceeds 1 year limit");

        updatePool();

        StakerInfo storage staker = stakers[msg.sender];
        if (staker.stakedLP > 0) {
            uint256 pending = (staker.stakedLP * accRewardsPerShare) / PRECISION - staker.rewardDebt;
            if (pending > 0) {
                uint256 boostedPending = applyNFTBoost(msg.sender, pending);
                rewardToken.transfer(msg.sender, boostedPending);
                emit RewardClaimed(msg.sender, boostedPending);
            }
        }

        lpShares[msg.sender] -= amount;
        staker.stakedLP += amount;
        totalStakedLP += amount;

        staker.lastStakedTimestamp = block.timestamp;
        staker.lockedUntil = block.timestamp + lockDuration;

        staker.rewardDebt = (staker.stakedLP * accRewardsPerShare) / PRECISION;

        emit Staked(msg.sender, amount, lockDuration);
    }

    function unstakeLP(uint256 amount) external nonReentrant {
        StakerInfo storage staker = stakers[msg.sender];
        require(staker.stakedLP >= amount, "Insufficient staked balance");
        require(block.timestamp >= staker.lockedUntil, "Tokens currently locked");

        updatePool();

        uint256 pending = (staker.stakedLP * accRewardsPerShare) / PRECISION - staker.rewardDebt;
        if (pending > 0) {
            uint256 boostedPending = applyNFTBoost(msg.sender, pending);
            rewardToken.transfer(msg.sender, boostedPending);
            emit RewardClaimed(msg.sender, boostedPending);
        }

        staker.stakedLP -= amount;
        totalStakedLP -= amount;
        lpShares[msg.sender] += amount;

        staker.rewardDebt = (staker.stakedLP * accRewardsPerShare) / PRECISION;

        emit Unstaked(msg.sender, amount);
    }

    function pendingRewards(address user) external view returns (uint256) {
        StakerInfo storage staker = stakers[user];
        uint256 _accRewardsPerShare = accRewardsPerShare;
        
        if (block.number > lastRewardBlock && totalStakedLP != 0) {
            uint256 multiplier = block.number - lastRewardBlock;
            uint256 nexusReward = multiplier * REWARDS_PER_BLOCK;
            _accRewardsPerShare += (nexusReward * PRECISION) / totalStakedLP;
        }

        uint256 baseRewards = (staker.stakedLP * _accRewardsPerShare) / PRECISION - staker.rewardDebt;
        return applyNFTBoost(user, baseRewards);
    }

    function claimRewards() external nonReentrant {
        updatePool();

        StakerInfo storage staker = stakers[msg.sender];
        uint256 pending = (staker.stakedLP * accRewardsPerShare) / PRECISION - staker.rewardDebt;
        require(pending > 0, "No rewards to claim");

        uint256 boostedPending = applyNFTBoost(msg.sender, pending);
        staker.rewardDebt = (staker.stakedLP * accRewardsPerShare) / PRECISION;

        rewardToken.transfer(msg.sender, boostedPending);

        emit RewardClaimed(msg.sender, boostedPending);
    }

    function applyNFTBoost(address user, uint256 baseAmount) public view returns (uint256) {
        if (address(nftMembership) != address(0)) {
            try nftMembership.balanceOf(user) returns (uint256 balance) {
                if (balance > 0) {
                    return baseAmount + (baseAmount * NFT_BOOST_PERCENT) / 100;
                }
            } catch {
                return baseAmount;
            }
        }
        return baseAmount;
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

    function setNFTMembership(address _nft) external onlyOwner {
        nftMembership = IERC721(_nft);
        emit ConfigUpdated(_nft);
    }
}