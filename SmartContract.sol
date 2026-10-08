// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Magnum Opus DeFi Nexus Engine Contract
 * @author Lead Principal Software Architect
 * @notice Combines an ERC20 token, DeFi Staking Vault with multi-tier rewards, 
 *         and a custom Flash Loan Provider in a single highly-optimized smart contract.
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

interface IFlashLoanReceiver {
    function executeOperation(uint256 amount, uint256 premium, address initiator, bytes calldata params) external returns (bool);
}

contract ReentrancyGuard {
    uint8 private _unlocked = 1;
    modifier nonReentrant() {
        require(_unlocked == 1, "REENTRANCY_GUARD_TRIGGERED");
        _unlocked = 0;
        _;
        _unlocked = 1;
    }
}

contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "OWNABLE_CALLER_NOT_OWNER");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "OWNABLE_NEW_OWNER_ZERO_ADDRESS");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);

    constructor() {
        _paused = false;
    }

    modifier whenNotPaused() {
        require(!_paused, "PAUSABLE_CONTRACT_IS_PAUSED");
        _;
    }

    modifier whenPaused() {
        require(_paused, "PAUSABLE_CONTRACT_NOT_PAUSED");
        _;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function pause() external onlyOwner whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

contract NexusToken is IERC20, Ownable {
    string public constant name = "Magnum Opus Nexus";
    string public constant symbol = "NXT";
    uint8 public constant decimals = 18;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Dynamic tax configuration for DeFi operations
    uint256 public transferTaxBps = 100; // 1% default tax
    address public taxVault;

    constructor(uint256 initialSupply, address _taxVault) {
        require(_taxVault != address(0), "NXT_INVALID_VAULT");
        taxVault = _taxVault;
        _mint(msg.sender, initialSupply);
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

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "NXT_TRANSFER_EXCEEDS_ALLOWANCE");
        unchecked {
            _approve(sender, msg.sender, currentAllowance - amount);
        }
        return true;
    }

    function setTransferTax(uint256 newTaxBps) external onlyOwner {
        require(newTaxBps <= 500, "NXT_TAX_TOO_HIGH"); // Max 5%
        transferTaxBps = newTaxBps;
    }

    function setTaxVault(address newVault) external onlyOwner {
        require(newVault != address(0), "NXT_INVALID_VAULT_ADDRESS");
        taxVault = newVault;
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "NXT_TRANSFER_FROM_ZERO_ADDRESS");
        require(recipient != address(0), "NXT_TRANSFER_TO_ZERO_ADDRESS");
        require(_balances[sender] >= amount, "NXT_TRANSFER_EXCEEDS_BALANCE");

        uint256 taxAmount = 0;
        if (transferTaxBps > 0 && sender != owner() && recipient != owner()) {
            taxAmount = (amount * transferTaxBps) / 10000;
        }

        uint256 netAmount = amount - taxAmount;

        unchecked {
            _balances[sender] -= amount;
            _balances[recipient] += netAmount;
        }
        emit Transfer(sender, recipient, netAmount);

        if (taxAmount > 0) {
            unchecked {
                _balances[taxVault] += taxAmount;
            }
            emit Transfer(sender, taxVault, taxAmount);
        }
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "NXT_MINT_TO_ZERO_ADDRESS");
        _totalSupply += amount;
        unchecked {
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "NXT_BURN_FROM_ZERO_ADDRESS");
        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "NXT_BURN_EXCEEDS_BALANCE");
        unchecked {
            _balances[account] = accountBalance - amount;
            _totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "NXT_APPROVE_FROM_ZERO_ADDRESS");
        require(spender != address(0), "NXT_APPROVE_TO_ZERO_ADDRESS");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}

contract MagnumOpusNexusDeFi is ReentrancyGuard, Pausable {
    
    struct UserInfo {
        uint256 stakedAmount;
        uint256 rewardDebt;
        uint256 lockUpPeriodEnd;
        uint256 lastDepositTime;
    }

    struct PoolInfo {
        IERC20 stakeToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accRewardPerShare;
        uint256 totalStaked;
        uint256 lockPeriodSeconds;
    }

    NexusToken public rewardToken;
    uint256 public rewardPerBlock = 10 * 1e18; // 10 NXT per block

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    uint256 public totalAllocPoint = 0;
    uint256 public startBlock;

    // Flash loan properties
    uint256 public flashLoanFeeBps = 9; // 0.09% fee

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 indexed pid, uint256 amount);
    event FlashLoanExecuted(address indexed receiver, uint256 amount, uint256 fee);

    constructor(address _rewardTokenAddress) {
        rewardToken = NexusToken(_rewardTokenAddress);
        startBlock = block.number;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function addPool(uint256 _allocPoint, address _stakeToken, uint256 _lockPeriodSeconds, bool _withUpdate) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint += _allocPoint;
        poolInfo.push(PoolInfo({
            stakeToken: IERC20(_stakeToken),
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accRewardPerShare: 0,
            totalStaked: 0,
            lockPeriodSeconds: _lockPeriodSeconds
        }));
    }

    function setPoolAllocPoint(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function getPendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 stakedSupply = pool.totalStaked;

        if (block.number > pool.lastRewardBlock && stakedSupply != 0) {
            uint256 multiplier = block.number - pool.lastRewardBlock;
            uint256 reward = (multiplier * rewardPerBlock * pool.allocPoint) / totalAllocPoint;
            accRewardPerShare += (reward * 1e12) / stakedSupply;
        }
        return ((user.stakedAmount * accRewardPerShare) / 1e12) - user.rewardDebt;
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 stakedSupply = pool.totalStaked;
        if (stakedSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = block.number - pool.lastRewardBlock;
        uint256 reward = (multiplier * rewardPerBlock * pool.allocPoint) / totalAllocPoint;
        
        // Mint reward tokens specifically for distribution
        rewardToken.mint(address(this), reward);

        pool.accRewardPerShare += (reward * 1e12) / stakedSupply;
        pool.lastRewardBlock = block.number;
    }

    function deposit(uint256 _pid, uint256 _amount) external nonReentrant whenNotPaused {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        if (user.stakedAmount > 0) {
            uint256 pending = ((user.stakedAmount * pool.accRewardPerShare) / 1e12) - user.rewardDebt;
            if (pending > 0) {
                safeRewardTransfer(msg.sender, pending);
                emit RewardPaid(msg.sender, _pid, pending);
            }join
        }

        if (_amount > 0) {
            pool.stakeToken.transferFrom(address(msg.sender), address(this), _amount);
            user.stakedAmount += _amount;
            pool.totalStaked += _amount;
            user.lastDepositTime = block.timestamp;
            user.lockUpPeriodEnd = block.timestamp + pool.lockPeriodSeconds;
        }

        user.rewardDebt = (user.stakedAmount * pool.accRewardPerShare) / 1e12;
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.stakedAmount >= _amount, "DEFI_WITHDRAW_EXCEEDS_STAKED");
        require(block.timestamp >= user.lockUpPeriodEnd, "DEFI_LOCKUP_STILL_ACTIVE");
        
        updatePool(_pid);
        uint256 pending = ((user.stakedAmount * pool.accRewardPerShare) / 1e12) - user.rewardDebt;
        if (pending > 0) {
            safeRewardTransfer(msg.sender, pending);
            emit RewardPaid(msg.sender, _pid, pending);
        }

        if (_amount > 0) {
            user.stakedAmount -= _amount;
            pool.totalStaked -= _amount;
            pool.stakeToken.transfer(address(msg.sender), _amount);
        }

        user.rewardDebt = (user.stakedAmount * pool.accRewardPerShare) / 1e12;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.stakedAmount;
        
        require(amount > 0, "DEFI_EMERGENCY_NO_STAKE");
        
        user.stakedAmount = 0;
        user.rewardDebt = 0;
        pool.totalStaked -= amount;
        
        pool.stakeToken.transfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    function safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 bal = rewardToken.balanceOf(address(this));
        if (_amount > bal) {
            rewardToken.transfer(_to, bal);
        } else {
            rewardToken.transfer(_to, _amount);
        }
    }

    function updateRewardPerBlock(uint256 _newReward) external onlyOwner {
        massUpdatePools();
        rewardPerBlock = _newReward;
    }

    // High performance Flash Loan system
    function flashLoan(address receiverAddress, uint256 amount, bytes calldata params) external nonReentrant whenNotPaused {
        uint256 balanceBefore = rewardToken.balanceOf(address(this));
        require(balanceBefore >= amount, "DEFI_FLASH_LOAN_INSUFFICIENT_LIQUIDITY");

        uint256 fee = (amount * flashLoanFeeBps) / 10000;
        
        // Transfer funds to receiver
        rewardToken.transfer(receiverAddress, amount);

        // Execute callback
        require(
            IFlashLoanReceiver(receiverAddress).executeOperation(amount, fee, msg.sender, params),
            "DEFI_FLASH_LOAN_EXECUTION_FAILED"
        );

        // Check if correct balance has been returned
        uint256 balanceAfter = rewardToken.balanceOf(address(this));
        require(balanceAfter >= balanceBefore + fee, "DEFI_FLASH_LOAN_NOT_PAID_BACK");

        emit FlashLoanExecuted(receiverAddress, amount, fee);
    }

    function setFlashLoanFee(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 500, "DEFI_FLASH_FEE_MAX_LIMIT"); // Max 5%
        flashLoanFeeBps = _feeBps;
    }
}