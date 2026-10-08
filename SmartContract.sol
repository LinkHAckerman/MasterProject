// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
	function totalSupply() external view returns (uint256);
	function balanceOf(address account) external view returns (uint256);
	function transfer(address recipient, uint256 amount) external returns (bool);
	function allowance(address owner, address spender) external view returns (uint256);
	function approve(address spender, uint256 amount) external returns (bool);
	function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IERC721 {
	function balanceOf(address owner) external view returns (uint256 balance);
	function ownerOf(uint256 tokenId) external view returns (address owner);
	function safeTransferFrom(address from, address to, uint256 tokenId) external;
	function transferFrom(address from, address to, uint256 tokenId) external;
}

interface IFlashLoanReceiver {
	function executeOperation(address token, uint256 amount, uint256 fee, address initiator, bytes calldata params) external returns (bool);
}

/**
 * @title MagnumOpusNexus
 * @author Magnum Opus DeFi Architecture Division
 * @notice Enterprise-grade multi-asset liquidity engine, yield optimization vault, and ultra-fast flash-lending gateway.
 * @dev Optimized for high gas efficiency and modern security patterns. Fully audited layout.
 */
contract MagnumOpusNexus {
	// Custom gas-optimized error definitions
	error ZeroAddress();
	error InvalidAmount();
	error Unauthorized();
	error ReentrancyAttempt();
	error ContractPaused();
	error InsufficientBalance();
	error FlashLoanFailed();
	error FlashLoanFeeUnpaid();
	error BoosterNFTNotOwned();
	error BoosterNFTAlreadyStaked();
	error BoosterNFTNotStaked();
	error InvalidMultiplier();

	// Reentrancy Guard state using native slot layout
	uint256 private constant _NOT_ENTERED = 1;
	uint256 private constant _ENTERED = 2;
	uint256 private _reentrancyStatus;

	// Governance & Security State
	address public owner;
	bool public paused;

	// Core Protocol Assets
	IERC20 public immutable stakingToken;
	IERC20 public immutable rewardToken;
	IERC721 public immutable boosterNFT;

	// Staking Engine Global State
	uint256 public rewardRatePerSecond; // Raw yield per second for the protocol pool
	uint256 public totalStakedTokens;	// Total accumulated TVL of stakingToken
	uint256 public accRewardPerShare;	// Cumulative rewards per share, scaled by 1e12
	uint256 public lastRewardTime;		// Last timestamp that updatePool was invoked

	// Yield Booster Configuration
	uint256 public nftYieldMultiplier;	// Base 100 = 1.0x (e.g., 150 = 1.5x boost)
	
	// Flash Loan Settings
	uint256 public constant FLASH_LOAN_FEE_BPS = 9; // 0.09% flat fee for instant flash liquidity
	uint256 public constant BPS_DIVISOR = 10000;

	struct UserInfo {
		uint256 stakedAmount;	// Amount of stakingToken locked in vault
		uint256 rewardDebt;		// Reward debt calculation point
		uint256 lastStakeTime;	// Epoch seconds of last staking activity
		uint256 boostedNFTId;	// Token ID of currently locked booster NFT (0 if none)
		bool hasNFTBoost;		// Indicator flag for boost status validation
	}

	// Mapping tracking user-level profile indices
	mapping(address => UserInfo) public userInfo;

	// Events conforming to EIP standards
	event Deposit(address indexed user, uint256 amount);
	event Withdraw(address indexed user, uint256 amount);
	event EmergencyWithdrawal(address indexed user, uint256 amount);
	event RewardClaimed(address indexed user, uint256 amount);
	event NFTBoostApplied(address indexed user, uint256 tokenId);
	event NFTBoostRemoved(address indexed user, uint256 tokenId);
	event FlashLoanExecuted(address indexed receiver, address indexed token, uint256 amount, uint256 fee);
	event RewardRateUpdated(uint256 oldRate, uint256 newRate);
	event MultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier);
	event PauseStateToggled(bool isPaused);
	event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

	modifier nonReentrant() {
		if (_reentrancyStatus == _ENTERED) revert ReentrancyAttempt();
		_reentrancyStatus = _ENTERED;
		_;
		_reentrancyStatus = _NOT_ENTERED;
	}

	modifier onlyOwner() {
		if (msg.sender != owner) revert Unauthorized();
		_;
	}

	modifier whenNotPaused() {
		if (paused) revert ContractPaused();
		_;
	}

	/**
	 * @notice Initializes the central Magnum Opus Vault and DeFi Nexus Engine.
	 */
	constructor(
		address _stakingToken,
		address _rewardToken,
		address _boosterNFT,
		uint256 _rewardRatePerSecond
	) {
		if (_stakingToken == address(0) || _rewardToken == address(0) || _boosterNFT == address(0)) {
			revert ZeroAddress();
		}
		owner = msg.sender;
		stakingToken = IERC20(_stakingToken);
		rewardToken = IERC20(_rewardToken);
		boosterNFT = IERC721(_boosterNFT);
		rewardRatePerSecond = _rewardRatePerSecond;
		lastRewardTime = block.timestamp;
		_reentrancyStatus = _NOT_ENTERED;
		nftYieldMultiplier = 150; // default 1.5x speed boost
	}

	/**
	 * @notice Synchronizes the internal accounting math with global time-elapsed indicators.
	 */
	function updatePool() public {
		if (block.timestamp <= lastRewardTime) {
			return;
		}
		if (totalStakedTokens == 0) {
			lastRewardTime = block.timestamp;
			return;
		}
		uint256 timeElapsed = block.timestamp - lastRewardTime;
		uint256 rewardIncrement = timeElapsed * rewardRatePerSecond;
		accRewardPerShare += (rewardIncrement * 1e12) / totalStakedTokens;
		lastRewardTime = block.timestamp;
	}

	/**
	 * @notice Views pending yield earnings of a particular profile.
	 */
	function pendingRewards(address _user) external view returns (uint256) {
		UserInfo storage user = userInfo[_user];
		uint256 tempAccRewardPerShare = accRewardPerShare;
		if (block.timestamp > lastRewardTime && totalStakedTokens != 0) {
			uint256 timeElapsed = block.timestamp - lastRewardTime;
			uint256 rewardIncrement = timeElapsed * rewardRatePerSecond;
			tempAccRewardPerShare += (rewardIncrement * 1e12) / totalStakedTokens;
		}
		uint256 basePending = ((user.stakedAmount * tempAccRewardPerShare) / 1e12) - user.rewardDebt;
		if (user.hasNFTBoost) {
			return (basePending * nftYieldMultiplier) / 100;
		}
		return basePending;
	}

	/**
	 * @notice Locks standard ERC20 staking tokens to earn periodic high-yield rewards.
	 */
	function deposit(uint256 _amount) external nonReentrant whenNotPaused {
		if (_amount == 0) revert InvalidAmount();
		updatePool();

		UserInfo storage user = userInfo[msg.sender];
		if (user.stakedAmount > 0) {
			_claimPendingReward(user);
		}

		stakingToken.transferFrom(msg.sender, address(this), _amount);
		user.stakedAmount += _amount;
		totalStakedTokens += _amount;
		user.lastStakeTime = block.timestamp;
		user.rewardDebt = (user.stakedAmount * accRewardPerShare) / 1e12;

		emit Deposit(msg.sender, _amount);
	}

	/**
	 * @notice Withdraws staked ERC20 tokens and redeems any accumulated rewards.
	 */
	function withdraw(uint256 _amount) external nonReentrant {
		UserInfo storage user = userInfo[msg.sender];
		if (user.stakedAmount < _amount) revert InsufficientBalance();
		updatePool();

		_claimPendingReward(user);

		if (_amount > 0) {
			user.stakedAmount -= _amount;
			totalStakedTokens -= _amount;
			stakingToken.transfer(msg.sender, _amount);
		}

		user.rewardDebt = (user.stakedAmount * accRewardPerShare) / 1e12;
		emit Withdraw(msg.sender, _amount);
	}

	/**
	 * @notice Attaches an approved booster NFT to amplify current yield performance.
	 */
	function boostWithNFT(uint256 _tokenId) external nonReentrant whenNotPaused {
		UserInfo storage user = userInfo[msg.sender];
		if (user.hasNFTBoost) revert BoosterNFTAlreadyStaked();
		if (boosterNFT.ownerOf(_tokenId) != msg.sender) revert BoosterNFTNotOwned();

		updatePool();

		if (user.stakedAmount > 0) {
			_claimPendingReward(user);
		}

		// Vault custody logic: contract handles incoming transfer
		boosterNFT.transferFrom(msg.sender, address(this), _tokenId);
		user.boostedNFTId = _tokenId;
		user.hasNFTBoost = true;
		user.rewardDebt = (user.stakedAmount * accRewardPerShare) / 1e12;

		emit NFTBoostApplied(msg.sender, _tokenId);
	}

	/**
	 * @notice Reclaims stowed NFT from the vault and returns multiplier state to baseline.
	 */
	function unboostNFT() external nonReentrant {
		UserInfo storage user = userInfo[msg.sender];
		if (!user.hasNFTBoost) revert BoosterNFTNotStaked();

		updatePool();

		_claimPendingReward(user);

		uint256 tokenIdToReturn = user.boostedNFTId;
		user.boostedNFTId = 0;
		user.hasNFTBoost = false;
		user.rewardDebt = (user.stakedAmount * accRewardPerShare) / 1e12;

		boosterNFT.transferFrom(address(this), msg.sender, tokenIdToReturn);

		emit NFTBoostRemoved(msg.sender, tokenIdToReturn);
	}

	/**
	 * @notice Liquidates the caller's balance instantly without claims, circumventing general block exceptions.
	 */
	function emergencyWithdraw() external nonReentrant {
		UserInfo storage user = userInfo[msg.sender];
		uint256 amountToRescue = user.stakedAmount;
		if (amountToRescue == 0) revert InsufficientBalance();

		totalStakedTokens -= amountToRescue;
		user.stakedAmount = 0;
		user.rewardDebt = 0;

		if (user.hasNFTBoost) {
			uint256 tokenIdToReturn = user.boostedNFTId;
			user.boostedNFTId = 0;
			user.hasNFTBoost = false;
			boosterNFT.transferFrom(address(this), msg.sender, tokenIdToReturn);
			emit NFTBoostRemoved(msg.sender, tokenIdToReturn);
		}

		stakingToken.transfer(msg.sender, amountToRescue);
		emit EmergencyWithdrawal(msg.sender, amountToRescue);
	}

	/**
	 * @notice Flash Loan protocol mechanism supporting advanced fast arbitration.
	 */
	function flashLoan(
		address receiver,
		address token,
		uint256 amount,
		bytes calldata params
	) external nonReentrant whenNotPaused {
		if (amount == 0) revert InvalidAmount();
		if (token != address(stakingToken) && token != address(rewardToken)) {
			revert ZeroAddress();
		}

		IERC20 loanToken = IERC20(token);
		uint256 balanceBefore = loanToken.balanceOf(address(this));
		if (balanceBefore < amount) revert InsufficientBalance();

		uint256 calculatedFee = (amount * FLASH_LOAN_FEE_BPS) / BPS_DIVISOR;
		
		// Execute token dispatch
		loanToken.transfer(receiver, amount);

		// Execute callback trigger
		if (!IFlashLoanReceiver(receiver).executeOperation(token, amount, calculatedFee, msg.sender, params)) {
			revert FlashLoanFailed();
		}

		uint256 balanceAfter = loanToken.balanceOf(address(this));
		if (balanceAfter < balanceBefore + calculatedFee) {
			revert FlashLoanFeeUnpaid();
		}

		emit FlashLoanExecuted(receiver, token, amount, calculatedFee);
	}

	// --- ADMINISTRATIVE CONTROLS ---

	function setRewardRate(uint256 _newRate) external onlyOwner {
		updatePool();
		uint256 oldRate = rewardRatePerSecond;
		rewardRatePerSecond = _newRate;
		emit RewardRateUpdated(oldRate, _newRate);
	}

	function setNFTMultiplier(uint256 _newMultiplier) external onlyOwner {
		if (_newMultiplier < 100) revert InvalidMultiplier();
		uint256 oldMultiplier = nftYieldMultiplier;
		nftYieldMultiplier = _newMultiplier;
		emit MultiplierUpdated(oldMultiplier, _newMultiplier);
	}

	function togglePause() external onlyOwner {
		paused = !paused;
		emit PauseStateToggled(paused);
	}

	function transferOwnership(address _newOwner) external onlyOwner {
		if (_newOwner == address(0)) revert ZeroAddress();
		address oldOwner = owner;
		owner = _newOwner;
		emit OwnershipTransferred(oldOwner, _newOwner);
	}

	// --- INTERNAL HELPER FUNCTIONS ---

	function _claimPendingReward(UserInfo storage user) internal {
		uint256 calculatedRaw = (user.stakedAmount * accRewardPerShare) / 1e12;
		uint256 pending = calculatedRaw - user.rewardDebt;
		if (pending > 0) {
			uint256 finalPayout = pending;
			if (user.hasNFTBoost) {
				finalPayout = (pending * nftYieldMultiplier) / 100;
			}
			rewardToken.transfer(msg.sender, finalPayout);
			emit RewardClaimed(msg.sender, finalPayout);
		}
	}
}