// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title MagnumOpusDeFiEngine
 * @notice The ultimate, high-performance decentralized finance hub.
 * Integrates ERC20, Automated Market Maker (Constant Product), Staking Vault, and Flash Loan capabilities.
 * Designed with strict security, custom errors, and gas-efficient storage layout.
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

interface IFlashLoanReceiver {
    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

contract ReentrancyGuard {
    uint8 private _unlocked = 1;
    modifier nonReentrant() {
        if (_unlocked != 1) revert ReentrantCall();
        _unlocked = 0;
        _;
        _unlocked = 1;
    }
    error ReentrantCall();
}

contract MagnumToken is IERC20 {
    string public constant name = "Magnum Nexus Token";
    string public constant symbol = "MAXS";
    uint8 public constant decimals = 18;
    
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    address public immutable governor;
    
    error OnlyGovernor();
    error TransferToZeroAddress();
    error TransferExceedsBalance();
    error AllowanceExceeded();

    modifier onlyGovernor() {
        if (msg.sender != governor) revert OnlyGovernor();
        _;
    }

    constructor(uint256 initialSupply) {
        governor = msg.sender;
        _mint(msg.sender, initialSupply);
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
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < value) revert AllowanceExceeded();
            _allowances[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function mint(address to, uint256 value) external onlyGovernor {
        _mint(to, value);
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (to == address(0)) revert TransferToZeroAddress();
        uint256 fromBalance = _balances[from];
        if (fromBalance < value) revert TransferExceedsBalance();
        _balances[from] = fromBalance - value;
        _balances[to] += value;
        emit Transfer(from, to, value);
    }

    function _mint(address account, uint256 value) internal {
        if (account == address(0)) revert TransferToZeroAddress();
        _totalSupply += value;
        _balances[account] += value;
        emit Transfer(address(0), account, value);
    }

    function _burn(address account, uint256 value) internal {
        uint256 accountBalance = _balances[account];
        if (accountBalance < value) revert TransferExceedsBalance();
        _balances[account] = accountBalance - value;
        _totalSupply -= value;
        emit Transfer(account, address(0), value);
    }
}

contract MagnumDeFiNexus is ReentrancyGuard {
    MagnumToken public immutable tokenA;
    IERC20 public immutable tokenB;
    
    uint256 public reserveA;
    uint256 public reserveB;
    
    uint256 public totalStaked;
    mapping(address => uint256) public stakeBalances;
    mapping(address => uint256) public rewardDebt;
    uint256 public accRewardPerShare;
    uint256 public lastRewardBlock;
    uint256 public rewardRatePerBlock = 2 * 10**16;
    
    uint256 public constant FLASH_LOAN_FEE_BPS = 30;
    
    mapping(address => uint256) public lpBalances;
    uint256 public totalLPSupply;

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpTokens);
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpTokens);
    event SwapExecuted(address indexed swapper, bool isAForB, uint256 amountIn, uint256 amountOut);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event FlashLoanExecuted(address indexed receiver, address indexed token, uint256 amount, uint256 fee);

    error InvalidAmount();
    error InsufficientLiquidity();
    error InsufficientK();
    error ExcessSlippage();
    error StakingRewardUpdateFailed();
    error FlashLoanUnpaid();
    error TransferFailed();

    constructor(address _tokenA, address _tokenB) {
        tokenA = MagnumToken(_tokenA);
        tokenB = IERC20(_tokenB);
        lastRewardBlock = block.number;
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256) {
        if (amountIn == 0) revert InvalidAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    function addLiquidity(uint256 amountADesired, uint256 amountBDesired) external nonReentrant returns (uint256 lpShares) {
        if (amountADesired == 0 || amountBDesired == 0) revert InvalidAmount();
        
        tokenA.transferFrom(msg.sender, address(this), amountADesired);
        tokenB.transferFrom(msg.sender, address(this), amountBDesired);

        uint256 _reserveA = reserveA;
        uint256 _reserveB = reserveB;

        if (_reserveA == 0 && _reserveB == 0) {
            lpShares = sqrt(amountADesired * amountBDesired);
        } else {
            uint256 shareA = (amountADesired * totalLPSupply) / _reserveA;
            uint256 shareB = (amountBDesired * totalLPSupply) / _reserveB;
            lpShares = shareA < shareB ? shareA : shareB;
        }

        if (lpShares == 0) revert InsufficientLiquidity();

        totalLPSupply += lpShares;
        lpBalances[msg.sender] += lpShares;

        reserveA = _reserveA + amountADesired;
        reserveB = _reserveB + amountBDesired;

        emit LiquidityAdded(msg.sender, amountADesired, amountBDesired, lpShares);
    }

    function removeLiquidity(uint256 lpShares) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        uint256 userLp = lpBalances[msg.sender];
        if (userLp < lpShares || lpShares == 0) revert InvalidAmount();

        uint256 _totalLPSupply = totalLPSupply;
        amountA = (lpShares * reserveA) / _totalLPSupply;
        amountB = (lpShares * reserveB) / _totalLPSupply;

        if (amountA == 0 || amountB == 0) revert InsufficientLiquidity();

        lpBalances[msg.sender] = userLp - lpShares;
        totalLPSupply = _totalLPSupply - lpShares;

        reserveA -= amountA;
        reserveB -= amountB;

        if (!tokenA.transfer(msg.sender, amountA)) revert TransferFailed();
        if (!tokenB.transfer(msg.sender, amountB)) revert TransferFailed();

        emit LiquidityRemoved(msg.sender, amountA, amountB, lpShares);
    }

    function swap(bool isAForB, uint256 amountIn, uint256 minAmountOut) external nonReentrant returns (uint256 amountOut) {
        if (amountIn == 0) revert InvalidAmount();

        uint256 _reserveA = reserveA;
        uint256 _reserveB = reserveB;

        if (isAForB) {
            amountOut = getAmountOut(amountIn, _reserveA, _reserveB);
            if (amountOut < minAmountOut) revert ExcessSlippage();
            
            tokenA.transferFrom(msg.sender, address(this), amountIn);
            tokenB.transfer(msg.sender, amountOut);
            
            reserveA = _reserveA + amountIn;
            reserveB = _reserveB - amountOut;
        } else {
            amountOut = getAmountOut(amountIn, _reserveB, _reserveA);
            if (amountOut < minAmountOut) revert ExcessSlippage();
            
            tokenB.transferFrom(msg.sender, address(this), amountIn);
            tokenA.transfer(msg.sender, amountOut);
            
            reserveB = _reserveB + amountIn;
            reserveA = _reserveA - amountOut;
        }

        emit SwapExecuted(msg.sender, isAForB, amountIn, amountOut);
    }

    function _updatePool() internal {
        if (block.number <= lastRewardBlock) return;
        if (totalStaked == 0) {
            lastRewardBlock = block.number;
            return;
        }
        uint256 blockMultiplier = block.number - lastRewardBlock;
        uint256 rewardAmount = blockMultiplier * rewardRatePerBlock;
        
        accRewardPerShare += (rewardAmount * 1e12) / totalStaked;
        lastRewardBlock = block.number;
    }

    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        _updatePool();

        if (stakeBalances[msg.sender] > 0) {
            uint256 pending = ((stakeBalances[msg.sender] * accRewardPerShare) / 1e12) - rewardDebt[msg.sender];
            if (pending > 0) {
                tokenA.mint(msg.sender, pending);
                emit RewardClaimed(msg.sender, pending);
            }
        }

        tokenA.transferFrom(msg.sender, address(this), amount);
        stakeBalances[msg.sender] += amount;
        totalStaked += amount;
        rewardDebt[msg.sender] = (stakeBalances[msg.sender] * accRewardPerShare) / 1e12;

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        uint256 userStaked = stakeBalances[msg.sender];
        if (amount == 0 || userStaked < amount) revert InvalidAmount();
        _updatePool();

        uint256 pending = ((userStaked * accRewardPerShare) / 1e12) - rewardDebt[msg.sender];
        if (pending > 0) {
            tokenA.mint(msg.sender, pending);
            emit RewardClaimed(msg.sender, pending);
        }

        stakeBalances[msg.sender] = userStaked - amount;
        totalStaked -= amount;
        rewardDebt[msg.sender] = (stakeBalances[msg.sender] * accRewardPerShare) / 1e12;

        tokenA.transfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    function pendingReward(address user) external view returns (uint256) {
        uint256 _accRewardPerShare = accRewardPerShare;
        if (block.number > lastRewardBlock && totalStaked != 0) {
            uint256 blockMultiplier = block.number - lastRewardBlock;
            uint256 rewardAmount = blockMultiplier * rewardRatePerBlock;
            _accRewardPerShare += (rewardAmount * 1e12) / totalStaked;
        }
        return ((stakeBalances[user] * _accRewardPerShare) / 1e12) - rewardDebt[user];
    }

    function flashLoan(
        address receiver,
        address token,
        uint256 amount,
        bytes calldata params
    ) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        
        IERC20 targetToken;
        if (token == address(tokenA)) {
            targetToken = IERC20(address(tokenA));
        } else if (token == address(tokenB)) {
            targetToken = tokenB;
        } else {
            revert InvalidAmount();
        }

        uint256 balanceBefore = targetToken.balanceOf(address(this));
        if (balanceBefore < amount) revert InsufficientLiquidity();

        uint256 fee = (amount * FLASH_LOAN_FEE_BPS) / 10000;

        if (!targetToken.transfer(receiver, amount)) revert TransferFailed();

        if (!IFlashLoanReceiver(receiver).executeOperation(token, amount, fee, msg.sender, params)) {
            revert FlashLoanUnpaid();
        }

        uint256 balanceAfter = targetToken.balanceOf(address(this));
        if (balanceAfter < balanceBefore + fee) revert FlashLoanUnpaid();

        if (token == address(tokenA)) {
            reserveA = balanceAfter;
        } else {
            reserveB = balanceAfter;
        }

        emit FlashLoanExecuted(receiver, token, amount, fee);
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