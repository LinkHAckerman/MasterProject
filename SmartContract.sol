// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MagnumOpusProtocol
 * @author Magnum Opus Lead Architect
 * @notice The ultimate, all-encompassing Solidity engine containing:
 *         1. Custom ERC20 Utility Token (OPUS) with a built-in tax and burn dynamic.
 *         2. Multi-Tiered Staking Hub with complex yield calculation.
 *         3. Automated Market Maker (AMM) Liquidity Pool for OPUS / ETH pairs.
 *         4. NFT Staking Registry with custom metadata integration and boosting mechanics.
 *         5. Flash Loan Vault offering zero-collateral instant loans.
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

interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

interface IFlashLoanReceiver {
    function executeOperation(uint256 amount, uint256 fee, bytes calldata params) external returns (bool);
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

contract OpusToken is IERC20, Ownable {
    string public constant name = "Magnum Opus Token";
    string public constant symbol = "OPUS";
    uint8 public constant decimals = 18;
    
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 public burnRate = 100; // 1% basis points
    uint256 public taxRate = 100;  // 1% basis points
    address public treasury;

    constructor(uint256 initialSupply, address _treasury) {
        treasury = _treasury;
        _mint(msg.sender, initialSupply);
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, msg.sender, currentAllowance - amount);
        }
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(_balances[sender] >= amount, "ERC20: transfer amount exceeds balance");

        uint256 burnAmount = (amount * burnRate) / 10000;
        uint256 taxAmount = (amount * taxRate) / 10000;
        uint256 sendAmount = amount - burnAmount - taxAmount;

        _balances[sender] -= amount;
        _balances[recipient] += sendAmount;
        emit Transfer(sender, recipient, sendAmount);

        if (burnAmount > 0) {
            _totalSupply -= burnAmount;
            emit Transfer(sender, address(0), burnAmount);
        }

        if (taxAmount > 0) {
            _balances[treasury] += taxAmount;
            emit Transfer(sender, treasury, taxAmount);
        }
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function setTaxConfig(uint256 _burnRate, uint256 _taxRate) external onlyOwner {
        require(_burnRate + _taxRate <= 1000, "Tax config too high");
        burnRate = _burnRate;
        taxRate = _taxRate;
    }
}

contract MagnumOpusNexus is ReentrancyGuard, Ownable {
    OpusToken public immutable opusToken;
    IERC721 public nftToken;

    // AMM state variables
    uint256 public reserveOpus;
    uint256 public reserveEth;

    // Staking structures
    struct Staker {
        uint256 stakedAmount;
        uint256 rewardDebt;
        uint256 lastStakeTime;
    }
    mapping(address => Staker) public stakers;
    uint256 public totalStakedOpus;
    uint256 public rewardRatePerBlock = 1e16; // 0.01 OPUS per block per staked token
    uint256 public lastRewardBlock;
    uint256 public accTokenPerShare;

    // NFT Boosting structures
    struct NFTStake {
        address owner;
        uint256 stakedTimestamp;
    }
    mapping(uint256 => NFTStake) public nftStakes;
    mapping(address => uint256) public nftBoostMultiplier; // 100 = 1.0x, 150 = 1.5x boost

    // Flash Loan state variables
    uint256 public constant FLASH_LOAN_FEE_BPS = 9; // 0.09%

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    
    event LiquidityAdded(uint256 opusAmount, uint256 ethAmount, uint256 lpTokens);
    event LiquidityRemoved(uint256 opusAmount, uint256 ethAmount, uint256 lpTokens);
    event AssetSwapped(address indexed sender, uint256 inputAmount, uint256 outputAmount, bool isOpusToEth);
    
    event NFTStaked(address indexed user, uint256 tokenId);
    event NFTUnstaked(address indexed user, uint256 tokenId);
    
    event FlashLoanExecuted(address indexed receiver, uint256 amount, uint256 fee);

    constructor(address _opusToken, address _nftToken) {
        opusToken = OpusToken(_opusToken);
        nftToken = IERC721(_nftToken);
        lastRewardBlock = block.number;
    }

    // --- STAKING ENGINE WITH MULTI-TIER REWARDS & NFT BOOST ---

    function updatePool() public {
        if (block.number <= lastRewardBlock) {
            return;
        }
        if (totalStakedOpus == 0) {
            lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = block.number - lastRewardBlock;
        uint256 tokenReward = multiplier * rewardRatePerBlock;
        accTokenPerShare += (tokenReward * 1e12) / totalStakedOpus;
        lastRewardBlock = block.number;
    }

    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");
        updatePool();
        
        Staker storage user = stakers[msg.sender];
        if (user.stakedAmount > 0) {
            uint256 pending = (user.stakedAmount * accTokenPerShare) / 1e12 - user.rewardDebt;
            if (pending > 0) {
                uint256 boostedPending = applyNFTBoost(msg.sender, pending);
                require(opusToken.transfer(msg.sender, boostedPending), "Reward transfer failed");
                emit RewardClaimed(msg.sender, boostedPending);
            }
        }
        
        require(opusToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        user.stakedAmount += amount;
        totalStakedOpus += amount;
        user.rewardDebt = (user.stakedAmount * accTokenPerShare) / 1e12;
        user.lastStakeTime = block.timestamp;
        
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        Staker storage user = stakers[msg.sender];
        require(user.stakedAmount >= amount, "Insufficient staked balance");
        updatePool();
        
        uint256 pending = (user.stakedAmount * accTokenPerShare) / 1e12 - user.rewardDebt;
        if (pending > 0) {
            uint256 boostedPending = applyNFTBoost(msg.sender, pending);
            require(opusToken.transfer(msg.sender, boostedPending), "Reward transfer failed");
            emit RewardClaimed(msg.sender, boostedPending);
        }
        
        user.stakedAmount -= amount;
        totalStakedOpus -= amount;
        user.rewardDebt = (user.stakedAmount * accTokenPerShare) / 1e12;
        
        require(opusToken.transfer(msg.sender, amount), "Unstake transfer failed");
        emit Unstaked(msg.sender, amount);
    }

    function applyNFTBoost(address staker, uint256 amount) public view returns (uint256) {
        uint256 multiplier = nftBoostMultiplier[staker];
        if (multiplier == 0) {
            return amount;
        }
        return (amount * (100 + multiplier)) / 100;
    }

    // --- NFT STAKING FOR YIELD BOOSTING ---

    function stakeNFT(uint256 tokenId) external nonReentrant {
        require(nftToken.ownerOf(tokenId) == msg.sender, "Not owner of NFT");
        nftToken.transferFrom(msg.sender, address(this), tokenId);

        nftStakes[tokenId] = NFTStake({
            owner: msg.sender,
            stakedTimestamp: block.timestamp
        });

        // Boost multiplier increases by 20% for each staked NFT
        nftBoostMultiplier[msg.sender] += 20;

        emit NFTStaked(msg.sender, tokenId);
    }

    function unstakeNFT(uint256 tokenId) external nonReentrant {
        require(nftStakes[tokenId].owner == msg.sender, "Not the staker of NFT");
        
        delete nftStakes[tokenId];
        if (nftBoostMultiplier[msg.sender] >= 20) {
            nftBoostMultiplier[msg.sender] -= 20;
        } else {
            nftBoostMultiplier[msg.sender] = 0;
        }

        nftToken.transferFrom(address(this), msg.sender, tokenId);
        emit NFTUnstaked(msg.sender, tokenId);
    }

    // --- BUILT-IN AUTOMATED MARKET MAKER (AMM) LIQUIDITY POOL ---

    function addLiquidity(uint256 opusAmount) external payable nonReentrant returns (uint256) {
        require(opusAmount > 0 && msg.value > 0, "Invalid liquidity amount");
        
        if (reserveOpus == 0 && reserveEth == 0) {
            require(opusToken.transferFrom(msg.sender, address(this), opusAmount), "Token transfer failed");
            reserveOpus = opusAmount;
            reserveEth = msg.value;
            emit LiquidityAdded(opusAmount, msg.value, opusAmount);
            return opusAmount;
        } else {
            uint256 tokenCalculated = (msg.value * reserveOpus) / reserveEth;
            require(opusAmount >= tokenCalculated, "Insufficient tokens provided");
            require(opusToken.transferFrom(msg.sender, address(this), tokenCalculated), "Token transfer failed");
            
            reserveOpus += tokenCalculated;
            reserveEth += msg.value;
            emit LiquidityAdded(tokenCalculated, msg.value, tokenCalculated);
            return tokenCalculated;
        }
    }

    function swapOpusForEth(uint256 opusIn, uint256 minEthOut) external nonReentrant {
        require(opusIn > 0, "Input amount zero");
        require(reserveOpus > 0 && reserveEth > 0, "No liquidity available");

        // Constant product formula with 0.3% fee: (x + dx) * (y - dy) = k
        uint256 opusInWithFee = opusIn * 997;
        uint256 numerator = opusInWithFee * reserveEth;
        uint256 denominator = (reserveOpus * 1000) + opusInWithFee;
        uint256 ethOut = numerator / denominator;

        require(ethOut >= minEthOut, "Slippage tolerance exceeded");
        require(address(this).balance >= ethOut, "Insufficient ETH in pool");

        require(opusToken.transferFrom(msg.sender, address(this), opusIn), "Token deposit failed");
        
        reserveOpus += opusIn;
        reserveEth -= ethOut;

        (bool success, ) = msg.sender.call{value: ethOut}("");
        require(success, "ETH transfer failed");

        emit AssetSwapped(msg.sender, opusIn, ethOut, true);
    }

    function swapEthForOpus(uint256 minOpusOut) external payable nonReentrant {
        require(msg.value > 0, "Input ETH amount zero");
        require(reserveOpus > 0 && reserveEth > 0, "No liquidity available");

        uint256 ethInWithFee = msg.value * 997;
        uint256 numerator = ethInWithFee * reserveOpus;
        uint256 denominator = (reserveEth * 1000) + ethInWithFee;
        uint256 opusOut = numerator / denominator;

        require(opusOut >= minOpusOut, "Slippage tolerance exceeded");
        require(opusToken.balanceOf(address(this)) >= opusOut, "Insufficient tokens in pool");

        reserveEth += msg.value;
        reserveOpus -= opusOut;

        require(opusToken.transfer(msg.sender, opusOut), "Token transfer failed");

        emit AssetSwapped(msg.sender, msg.value, opusOut, false);
    }

    // --- HIGH-PERFORMANCE ON-CHAIN FLASH LOANS ---

    function executeFlashLoan(address receiverAddress, uint256 amount, bytes calldata params) external nonReentrant {
        uint256 balanceBefore = opusToken.balanceOf(address(this));
        require(balanceBefore >= amount, "Insufficient balance for Flash Loan");

        uint256 fee = (amount * FLASH_LOAN_FEE_BPS) / 10000;
        
        require(opusToken.transfer(receiverAddress, amount), "Flash loan transfer failed");

        require(
            IFlashLoanReceiver(receiverAddress).executeOperation(amount, fee, params),
            "Flash loan execution failed"
        );

        uint256 balanceAfter = opusToken.balanceOf(address(this));
        require(balanceAfter >= balanceBefore + fee, "Flash loan not returned with fee");

        emit FlashLoanExecuted(receiverAddress, amount, fee);
    }

    // --- PROTOCOL GOVERNANCE & UTILITIES ---

    receive() external payable {}

    function recoverTokens(address tokenAddress, uint256 amount) external onlyOwner {
        require(tokenAddress != address(opusToken), "Cannot recover system tokens");
        IERC20(tokenAddress).transfer(msg.sender, amount);
    }
}