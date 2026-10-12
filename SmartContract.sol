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
    mapping(address => uint256) public rewards;
    mapping(address => uint256) private _balances;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 newRate);

    modifier onlyOwner() {
        require(msg.sender == owner, "StakingVault: caller is not owner");
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    constructor(address _stakingToken, address _rewardToken) {
        owner = msg.sender;
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (((block.timestamp - lastUpdateTime) * rewardRate * 1e18) / totalStaked);
    }

    function earned(address account) public view returns (uint256) {
        return ((_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) + rewards[account];
    }

    function stake(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "StakingVault: cannot stake 0");
        totalStaked += amount;
        _balances[msg.sender] += amount;
        require(stakingToken.transferFrom(msg.sender, address(this), amount), "StakingVault: transfer failed");
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "StakingVault: cannot withdraw 0");
        require(_balances[msg.sender] >= amount, "StakingVault: insufficient balance");
        totalStaked -= amount;
        _balances[msg.sender] -= amount;
        require(stakingToken.transfer(msg.sender, amount), "StakingVault: transfer failed");
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() external updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            require(rewardToken.transfer(msg.sender, reward), "StakingVault: reward transfer failed");
            emit RewardPaid(msg.sender, reward);
        }
    }

    function setRewardRate(uint256 _rewardRate) external onlyOwner updateReward(address(0)) {
        rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate);
    }
}

/**
 * @title MagnumOpusDEX
 * @notice Constant-Product Automated Market Maker (AMM) supporting token pairs and liquidity management.
 */
contract MagnumOpusDEX {
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public reserve0;
    uint256 public reserve1;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    event MintLiquidity(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event BurnLiquidity(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Swap(address indexed trader, uint256 amountIn, IERC20 tokenIn, uint256 amountOut, IERC20 tokenOut);

    constructor(address _token0, address _token1) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    function _mint(address to, uint256 amount) private {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function _burn(address from, uint256 amount) private {
        balanceOf[from] -= amount;
        totalSupply -= amount;
    }

    function _update(uint256 balance0, uint256 balance1) private {
        reserve0 = balance0;
        reserve1 = balance1;
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

    function _min(uint256 x, uint256 y) private pure returns (uint256) {
        return x < y ? x : y;
    }

    function addLiquidity(uint256 amount0Desired, uint256 amount1Desired) external returns (uint256 liquidity) {
        require(token0.transferFrom(msg.sender, address(this), amount0Desired), "DEX: token0 transfer failed");
        require(token1.transferFrom(msg.sender, address(this), amount1Desired), "DEX: token1 transfer failed");

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;

        if (totalSupply == 0) {
            liquidity = _sqrt(amount0 * amount1);
        } else {
            liquidity = _min(
                (amount0 * totalSupply) / reserve0,
                (amount1 * totalSupply) / reserve1
            );
        }

        require(liquidity > 0, "DEX: liquidity is 0");
        _mint(msg.sender, liquidity);
        _update(balance0, balance1);

        emit MintLiquidity(msg.sender, amount0, amount1, liquidity);
    }

    function removeLiquidity(uint256 liquidity) external returns (uint256 amount0, uint256 amount1) {
        require(balanceOf[msg.sender] >= liquidity, "DEX: insufficient liquidity shares");

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        amount0 = (liquidity * balance0) / totalSupply;
        amount1 = (liquidity * balance1) / totalSupply;

        require(amount0 > 0 && amount1 > 0, "DEX: zero output amount");

        _burn(msg.sender, liquidity);
        require(token0.transfer(msg.sender, amount0), "DEX: token0 transfer failed");
        require(token1.transfer(msg.sender, amount1), "DEX: token1 transfer failed");

        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));

        emit BurnLiquidity(msg.sender, amount0, amount1, liquidity);
    }

    function swap(address tokenIn, uint256 amountIn, uint256 minOut) external returns (uint256 amountOut) {
        require(tokenIn == address(token0) || tokenIn == address(token1), "DEX: invalid token");
        require(amountIn > 0, "DEX: amountIn must be > 0");

        bool isToken0 = tokenIn == address(token0);
        (IERC20 inToken, IERC20 outToken, uint256 resIn, uint256 resOut) = isToken0
            ? (token0, token1, reserve0, reserve1)
            : (token1, token0, reserve1, reserve0);

        require(inToken.transferFrom(msg.sender, address(this), amountIn), "DEX: input transfer failed");

        uint256 amountInWithFee = amountIn * 997;
        amountOut = (amountInWithFee * resOut) / ((resIn * 1000) + amountInWithFee);

        require(amountOut >= minOut, "DEX: slippage exceeded");
        require(outToken.transfer(msg.sender, amountOut), "DEX: output transfer failed");

        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));

        emit Swap(msg.sender, amountIn, inToken, amountOut, outToken);
    }
}
