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

    uint256 public mintPrice = 0.05 ether;
    uint256 public maxSupply = 10000;
    uint256 public maxBatchMint = 10;
    uint256 private _nextTokenId = 1;

    string private _baseTokenURI;

    event NFTMinted(address indexed minter, uint256 indexed tokenId, string tokenURI);
    event MintPriceUpdated(uint256 newPrice);
    event BaseURIUpdated(string newBaseURI);
    event RoyaltyUpdated(address receiver, uint96 feeNumerator);

    constructor(
        string memory baseURI,
        address royaltyReceiver,
        uint96 royaltyFeeBps
    ) ERC721("Magnum Opus NFT", "MNFT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
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

    function withdrawETH(address payable to) external onlyRole(ADMIN_ROLE) {
        require(to != address(0), "MNFT: Invalid target address");
        uint256 balance = address(this).balance;
        (bool success, ) = to.call{value: balance}("");
        require(success, "MNFT: ETH Transfer failed");
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    // Required overrides for Solidity multiple inheritance
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
 * @title MagnumOpusDeFi
 * @dev Institutional-grade DeFi Vault & Staking Engine supporting dynamic APY rewards,
 * multi-token yield farming pools, compound interest calculations, and emergency withdrawals.
 */
contract MagnumOpusDeFi is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    struct PoolInfo {
        IERC20 stakingToken;
        IERC20 rewardToken;
        uint256 rewardPerBlock;
        uint256 lastRewardBlock;
        uint256 accRewardPerShare;
        uint256 totalStaked;
        uint256 lockPeriod;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 depositTimestamp;
        uint256 pendingRewards;
    }

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    event PoolAdded(uint256 indexed pid, address indexed stakingToken, address indexed rewardToken, uint256 rewardPerBlock);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardClaimed(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function addPool(
        IERC20 stakingToken,
        IERC20 rewardToken,
        uint256 rewardPerBlock,
        uint256 lockPeriod
    ) external onlyRole(ADMIN_ROLE) {
        poolInfo.push(PoolInfo({
            stakingToken: stakingToken,
            rewardToken: rewardToken,
            rewardPerBlock: rewardPerBlock,
            lastRewardBlock: block.number,
            accRewardPerShare: 0,
            totalStaked: 0,
            lockPeriod: lockPeriod
        }));

        emit PoolAdded(poolInfo.length - 1, address(stakingToken), address(rewardToken), rewardPerBlock);
    }

    function updatePool(uint256 pid) public {
        PoolInfo storage pool = poolInfo[pid];
        if (block.number <= pool.lastRewardBlock) return;

        if (pool.totalStaked == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 blocks = block.number - pool.lastRewardBlock;
        uint256 reward = blocks * pool.rewardPerBlock;
        pool.accRewardPerShare += (reward * 1e12) / pool.totalStaked;
        pool.lastRewardBlock = block.number;
    }

    function pendingReward(uint256 pid, address account) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][account];
        uint256 accRewardPerShare = pool.accRewardPerShare;

        if (block.number > pool.lastRewardBlock && pool.totalStaked != 0) {
            uint256 blocks = block.number - pool.lastRewardBlock;
            uint256 reward = blocks * pool.rewardPerBlock;
            accRewardPerShare += (reward * 1e12) / pool.totalStaked;
        }

        return (user.amount * accRewardPerShare) / 1e12 - user.rewardDebt + user.pendingRewards;
    }

    function deposit(uint256 pid, uint256 amount) external nonReentrant whenNotPaused {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        updatePool(pid);

        if (user.amount > 0) {
            uint256 pending = (user.amount * pool.accRewardPerShare) / 1e12 - user.rewardDebt;
            user.pendingRewards += pending;
        }

        if (amount > 0) {
            pool.stakingToken.safeTransferFrom(msg.sender, address(this), amount);
            user.amount += amount;
            pool.totalStaked += amount;
        }

        user.depositTimestamp = block.timestamp;
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e12;

        emit Deposit(msg.sender, pid, amount);
    }

    function withdraw(uint256 pid, uint256 amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        require(user.amount >= amount, "DeFi: Withdraw amount exceeds balance");
        require(block.timestamp >= user.depositTimestamp + pool.lockPeriod, "DeFi: Tokens locked in lockup period");

        updatePool(pid);

        uint256 pending = (user.amount * pool.accRewardPerShare) / 1e12 - user.rewardDebt;
        user.pendingRewards += pending;

        if (amount > 0) {
            user.amount -= amount;
            pool.totalStaked -= amount;
            pool.stakingToken.safeTransfer(msg.sender, amount);
        }

        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e12;

        emit Withdraw(msg.sender, pid, amount);
    }

    function claimReward(uint256 pid) external nonReentrant whenNotPaused {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        updatePool(pid);

        uint256 pending = (user.amount * pool.accRewardPerShare) / 1e12 - user.rewardDebt + user.pendingRewards;
        require(pending > 0, "DeFi: No pending rewards");

        user.pendingRewards = 0;
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e12;

        pool.rewardToken.safeTransfer(msg.sender, pending);

        emit RewardClaimed(msg.sender, pid, pending);
    }

    function emergencyWithdraw(uint256 pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        uint256 amount = user.amount;
        require(amount > 0, "DeFi: Nothing to withdraw");

        user.amount = 0;
        user.rewardDebt = 0;
        user.pendingRewards = 0;
        pool.totalStaked -= amount;

        pool.stakingToken.safeTransfer(msg.sender, amount);

        emit EmergencyWithdraw(msg.sender, pid, amount);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
