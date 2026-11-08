// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MagnumOpusToken
 * @dev Native governance & utility token for the Magnum Opus Multi-Chain Protocol.
 * Implements ERC20 standard with access-controlled minting, burning, permit functionality, and pause controls.
 */
contract MagnumOpusToken is ERC20, ERC20Burnable, ERC20Permit, AccessControl, Pausable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public immutable maxSupply;

    event MaxSupplyUpdated(uint256 newMaxSupply);

    constructor(uint256 initialSupply, uint256 cap)
        ERC20("Magnum Opus", "MOP")
        ERC20Permit("Magnum Opus")
    {
        require(cap >= initialSupply, "MOP: Cap must be >= initial supply");
        maxSupply = cap;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);

        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply);
        }
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(totalSupply() + amount <= maxSupply, "MOP: Exceeds max supply cap");
        _mint(to, amount);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20)
        whenNotPaused
    {
        super._update(from, to, value);
    }
}

/**
 * @title MagnumOpusNFT
 * @dev Multi-chain dynamic NFT contract with ERC721 Enumerable, URI Storage, and ERC2981 Royalties.
 */
contract MagnumOpusNFT is ERC721, ERC721Enumerable, ERC721URIStorage, ERC2981, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public mintPrice = 0.05 ether;
    uint256 public maxSupply = 10000;
    uint256 public maxBatchMint = 10;
    uint256 private _nextTokenId = 1;

    string private _baseTokenURI;

    event NFTMinted(address indexed minter, uint256 indexed tokenId, string tokenURI);
    event MintPriceUpdated(uint256 newPrice);
    event BaseURIUpdated(string newBaseURI);
    event RoyaltyUpdated(address receiver, uint96 feeNumerator);
    event FundsWithdrawn(address indexed recipient, uint256 amount);

    constructor(
        string memory baseURI,
        address royaltyReceiver,
        uint96 royaltyFeeBps
    ) ERC721("Magnum Opus NFT", "MNFT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _baseTokenURI = baseURI;

        _setDefaultRoyalty(royaltyReceiver, royaltyFeeBps);
    }

    function publicMint(string calldata customURI) external payable nonReentrant whenNotPaused {
        require(msg.value >= mintPrice, "MNFT: Insufficient payment");
        require(_nextTokenId <= maxSupply, "MNFT: Max supply reached");

        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);
        if (bytes(customURI).length > 0) {
            _setTokenURI(tokenId, customURI);
        }

        emit NFTMinted(msg.sender, tokenId, customURI);
    }

    function batchMint(address to, uint256 count) external onlyRole(MINTER_ROLE) {
        require(count > 0 && count <= maxBatchMint, "MNFT: Invalid batch size");
        require(_nextTokenId + count - 1 <= maxSupply, "MNFT: Exceeds max supply");

        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(to, tokenId);
            emit NFTMinted(to, tokenId, "");
        }
    }

    function setMintPrice(uint256 newPrice) external onlyRole(ADMIN_ROLE) {
        mintPrice = newPrice;
        emit MintPriceUpdated(newPrice);
    }

    function setBaseURI(string calldata newBaseURI) external onlyRole(ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    function setRoyalty(address receiver, uint96 feeNumerator) external onlyRole(ADMIN_ROLE) {
        _setDefaultRoyalty(receiver, feeNumerator);
        emit RoyaltyUpdated(receiver, feeNumerator);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function withdraw(address payable recipient) external onlyRole(ADMIN_ROLE) nonReentrant {
        require(recipient != address(0), "MNFT: Zero address recipient");
        uint256 balance = address(this).balance;
        require(balance > 0, "MNFT: No ETH balance");
        (bool success, ) = recipient.call{value: balance}("");
        require(success, "MNFT: Transfer failed");
        emit FundsWithdrawn(recipient, balance);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage, ERC2981, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

/**
 * @title MagnumOpusStaking
 * @dev Multi-tier DeFi staking vault supporting lockup tiers, yield multipliers, and emergency unstake.
 */
contract MagnumOpusStaking is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    struct TierInfo {
        uint256 lockDuration; // in seconds
        uint256 multiplierBps; // 10000 = 1.0x, 15000 = 1.5x
        bool enabled;
    }

    struct Stake {
        uint256 amount;
        uint256 weightedAmount;
        uint256 startTime;
        uint256 unlockTime;
        uint256 rewardDebt;
        uint8 tierIndex;
        bool withdrawn;
    }

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant EMERGENCY_PENALTY_BPS = 1000; // 10% penalty on early exit
    uint256 public accRewardPerShare;
    uint256 public lastRewardTime;
    uint256 public rewardRatePerSecond;
    uint256 public totalWeightedStake;
    address public treasury;

    TierInfo[] public tiers;
    mapping(address => Stake[]) public userStakes;

    event Staked(address indexed user, uint256 indexed stakeId, uint256 amount, uint8 tierIndex, uint256 unlockTime);
    event Unstaked(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 reward);
    event EmergencyUnstaked(address indexed user, uint256 indexed stakeId, uint256 returnedAmount, uint256 penalty);
    event RewardClaimed(address indexed user, uint256 indexed stakeId, uint256 reward);
    event RewardRateUpdated(uint256 newRate);
    event TierConfigured(uint8 indexed tierIndex, uint256 lockDuration, uint256 multiplierBps, bool enabled);

    constructor(address _stakingToken, address _rewardToken, address _treasury) {
        require(_stakingToken != address(0) && _rewardToken != address(0), "Invalid token addresses");
        require(_treasury != address(0), "Invalid treasury address");

        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        treasury = _treasury;
        lastRewardTime = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(DISTRIBUTOR_ROLE, msg.sender);

        // Standard lock tiers: Flexible, 30 days, 90 days, 180 days, 365 days
        tiers.push(TierInfo({lockDuration: 0, multiplierBps: 10000, enabled: true}));
        tiers.push(TierInfo({lockDuration: 30 days, multiplierBps: 12500, enabled: true}));
        tiers.push(TierInfo({lockDuration: 90 days, multiplierBps: 15000, enabled: true}));
        tiers.push(TierInfo({lockDuration: 180 days, multiplierBps: 20000, enabled: true}));
        tiers.push(TierInfo({lockDuration: 365 days, multiplierBps: 30000, enabled: true}));
    }

    function updatePool() public {
        if (block.timestamp <= lastRewardTime) {
            return;
        }

        if (totalWeightedStake == 0) {
            lastRewardTime = block.timestamp;
            return;
        }

        uint256 elapsed = block.timestamp - lastRewardTime;
        uint256 reward = elapsed * rewardRatePerSecond;
        accRewardPerShare += (reward * PRECISION) / totalWeightedStake;
        lastRewardTime = block.timestamp;
    }

    function stake(uint256 amount, uint8 tierIndex) external nonReentrant whenNotPaused {
        require(amount > 0, "Cannot stake 0");
        require(tierIndex < tiers.length, "Invalid tier index");
        TierInfo memory tier = tiers[tierIndex];
        require(tier.enabled, "Tier is disabled");

        updatePool();

        uint256 weighted = (amount * tier.multiplierBps) / 10000;
        totalWeightedStake += weighted;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 stakeId = userStakes[msg.sender].length;
        userStakes[msg.sender].push(Stake({
            amount: amount,
            weightedAmount: weighted,
            startTime: block.timestamp,
            unlockTime: block.timestamp + tier.lockDuration,
            rewardDebt: (weighted * accRewardPerShare) / PRECISION,
            tierIndex: tierIndex,
            withdrawn: false
        }));

        emit Staked(msg.sender, stakeId, amount, tierIndex, block.timestamp + tier.lockDuration);
    }

    function pendingReward(address account, uint256 stakeId) public view returns (uint256) {
        if (stakeId >= userStakes[account].length) return 0;
        Stake memory st = userStakes[account][stakeId];
        if (st.withdrawn) return 0;

        uint256 currentAcc = accRewardPerShare;
        if (block.timestamp > lastRewardTime && totalWeightedStake > 0) {
            uint256 elapsed = block.timestamp - lastRewardTime;
            uint256 reward = elapsed * rewardRatePerSecond;
            currentAcc += (reward * PRECISION) / totalWeightedStake;
        }

        uint256 accumulated = (st.weightedAmount * currentAcc) / PRECISION;
        if (accumulated > st.rewardDebt) {
            return accumulated - st.rewardDebt;
        }
        return 0;
    }

    function claimReward(uint256 stakeId) public nonReentrant whenNotPaused {
        require(stakeId < userStakes[msg.sender].length, "Invalid stake ID");
        Stake storage st = userStakes[msg.sender][stakeId];
        require(!st.withdrawn, "Stake already withdrawn");

        updatePool();

        uint256 reward = ((st.weightedAmount * accRewardPerShare) / PRECISION) - st.rewardDebt;
        if (reward > 0) {
            st.rewardDebt = (st.weightedAmount * accRewardPerShare) / PRECISION;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardClaimed(msg.sender, stakeId, reward);
        }
    }

    function unstake(uint256 stakeId) external nonReentrant {
        require(stakeId < userStakes[msg.sender].length, "Invalid stake ID");
        Stake storage st = userStakes[msg.sender][stakeId];
        require(!st.withdrawn, "Stake already withdrawn");
        require(block.timestamp >= st.unlockTime, "Tokens are still locked");

        updatePool();

        uint256 reward = ((st.weightedAmount * accRewardPerShare) / PRECISION) - st.rewardDebt;
        uint256 amountToReturn = st.amount;
        totalWeightedStake -= st.weightedAmount;
        st.withdrawn = true;

        if (reward > 0) {
            rewardToken.safeTransfer(msg.sender, reward);
        }
        stakingToken.safeTransfer(msg.sender, amountToReturn);

        emit Unstaked(msg.sender, stakeId, amountToReturn, reward);
    }

    function emergencyUnstake(uint256 stakeId) external nonReentrant {
        require(stakeId < userStakes[msg.sender].length, "Invalid stake ID");
        Stake storage st = userStakes[msg.sender][stakeId];
        require(!st.withdrawn, "Stake already withdrawn");

        updatePool();
        totalWeightedStake -= st.weightedAmount;
        st.withdrawn = true;

        uint256 penalty = (st.amount * EMERGENCY_PENALTY_BPS) / 10000;
        uint256 netAmount = st.amount - penalty;

        if (penalty > 0) {
            stakingToken.safeTransfer(treasury, penalty);
        }
        stakingToken.safeTransfer(msg.sender, netAmount);

        emit EmergencyUnstaked(msg.sender, stakeId, netAmount, penalty);
    }

    function setRewardRate(uint256 newRate) external onlyRole(DISTRIBUTOR_ROLE) {
        updatePool();
        rewardRatePerSecond = newRate;
        emit RewardRateUpdated(newRate);
    }

    function configureTier(uint8 tierIndex, uint256 lockDuration, uint256 multiplierBps, bool enabled) external onlyRole(ADMIN_ROLE) {
        if (tierIndex < tiers.length) {
            tiers[tierIndex] = TierInfo(lockDuration, multiplierBps, enabled);
        } else {
            require(tierIndex == tiers.length, "Invalid index for push");
            tiers.push(TierInfo(lockDuration, multiplierBps, enabled));
        }
        emit TierConfigured(tierIndex, lockDuration, multiplierBps, enabled);
    }

    function getUserStakeCount(address account) external view returns (uint256) {
        return userStakes[account].length;
    }
}

/**
 * @title MagnumOpusAMM
 * @dev Constant-product AMM liquidity pair (x * y = k) with TWAP oracle price accumulation.
 */
contract MagnumOpusAMM is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to);
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor(address _token0, address _token1) ERC20("Magnum Opus LP", "MOP-LP") {
        require(_token0 != address(0) && _token1 != address(0), "AMM: Zero token");
        require(_token0 != _token1, "AMM: Identical tokens");

        if (_token0 < _token1) {
            token0 = IERC20(_token0);
            token1 = IERC20(_token1);
        } else {
            token0 = IERC20(_token1);
            token1 = IERC20(_token0);
        }
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _updateReserves(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "AMM: Overflow");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;

        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            price0CumulativeLast += uint256((uint256(_reserve1) << 112) / _reserve0) * timeElapsed;
            price1CumulativeLast += uint256((uint256(_reserve0) << 112) / _reserve1) * timeElapsed;
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        address to
    ) external nonReentrant returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 amount0;
        uint256 amount1;

        if (_reserve0 == 0 && _reserve1 == 0) {
            amount0 = amount0Desired;
            amount1 = amount1Desired;
        } else {
            uint256 amount1Optimal = (amount0Desired * _reserve1) / _reserve0;
            if (amount1Optimal <= amount1Desired) {
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = (amount1Desired * _reserve0) / _reserve1;
                require(amount0Optimal <= amount0Desired, "AMM: Calculation error");
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
            }
        }

        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        uint256 total = totalSupply();
        if (total == 0) {
            liquidity = _sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0xdead), MINIMUM_LIQUIDITY); // Permanently lock first LP tokens
        } else {
            liquidity = _min((amount0 * total) / _reserve0, (amount1 * total) / _reserve1);
        }

        require(liquidity > 0, "AMM: Insufficient liquidity minted");
        _mint(to, liquidity);
        _updateReserves(token0.balanceOf(address(this)), token1.balanceOf(address(this)), _reserve0, _reserve1);
        emit Mint(msg.sender, amount0, amount1);
    }

    function removeLiquidity(
        uint256 liquidity,
        address to
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        require(liquidity > 0, "AMM: Invalid liquidity");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 total = totalSupply();

        amount0 = (liquidity * token0.balanceOf(address(this))) / total;
        amount1 = (liquidity * token1.balanceOf(address(this))) / total;
        require(amount0 > 0 && amount1 > 0, "AMM: Insufficient output");

        _burn(msg.sender, liquidity);
        token0.safeTransfer(to, amount0);
        token1.safeTransfer(to, amount1);

        _updateReserves(token0.balanceOf(address(this)), token1.balanceOf(address(this)), _reserve0, _reserve1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to
    ) external nonReentrant {
        require(amount0Out > 0 || amount1Out > 0, "AMM: Insufficient output amount");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "AMM: Insufficient liquidity");

        if (amount0Out > 0) token0.safeTransfer(to, amount0Out);
        if (amount1Out > 0) token1.safeTransfer(to, amount1Out);

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "AMM: Insufficient input amount");

        // 0.3% protocol fee (997/1000 multiplier)
        uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
        uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);
        require(balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * _reserve1 * 1000000, "AMM: K-Invariant violated");

        _updateReserves(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
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
}
