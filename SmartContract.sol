// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Magnum Opus Token (ERC20)
 * @dev Standard ERC20 with burn, permit and owner‑mint capabilities.
 */
contract MagnumOpusToken is ERC20, ERC20Burnable, ERC20Permit, Ownable {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18;

    constructor() ERC20("Magnum Opus Token", "MOPUS") ERC20Permit("Magnum Opus Token") {
        _mint(msg.sender, 500_000_000 * 1e18);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount);
    }
}

/**
 * @title Magnum Opus NFT (ERC721)
 * @dev Simple ERC721 with URI storage, mintable by contract owner.
 */
contract MagnumOpusNFT is ERC721URIStorage, Ownable {
    uint256 public nextTokenId;

    constructor() ERC721("Magnum Opus NFT", "MOPUSNFT") {}

    function mint(address to, string memory uri) external onlyOwner {
        uint256 tokenId = nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }
}

/**
 * @title StakingPool
 * @dev Single‑token staking pool with per‑second rewards, safe withdraws and reward accounting.
 */
contract StakingPool is ReentrancyGuard, Ownable {
    struct StakeInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastStakeTime;
    }

    MagnumOpusToken public immutable token;
    uint256 public rewardPerSecond;
    uint256 public accRewardPerShare; // scaled by 1e18
    uint256 public lastRewardTime;
    uint256 public totalStaked;
    mapping(address => StakeInfo) public stakes;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(MagnumOpusToken _token, uint256 _rewardPerSecond) {
        token = _token;
        rewardPerSecond = _rewardPerSecond;
        lastRewardTime = block.timestamp;
    }

    function updatePool() public {
        if (block.timestamp <= lastRewardTime) return;
        if (totalStaked == 0) {
            lastRewardTime = block.timestamp;
            return;
        }
        uint256 elapsed = block.timestamp - lastRewardTime;
        uint256 reward = elapsed * rewardPerSecond;
        accRewardPerShare += (reward * 1e18) / totalStaked;
        lastRewardTime = block.timestamp;
    }

    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero amount");
        updatePool();
        StakeInfo storage user = stakes[msg.sender];
        if (user.amount > 0) {
            uint256 pending = (user.amount * accRewardPerShare) / 1e18 - user.rewardDebt;
            if (pending > 0) {
                token.transfer(msg.sender, pending);
                emit RewardPaid(msg.sender, pending);
            }
        }
        token.transferFrom(msg.sender, address(this), amount);
        user.amount += amount;
        totalStaked += amount;
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e18;
        user.lastStakeTime = block.timestamp;
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        StakeInfo storage user = stakes[msg.sender];
        require(user.amount >= amount, "Insufficient stake");
        updatePool();
        uint256 pending = (user.amount * accRewardPerShare) / 1e18 - user.rewardDebt;
        if (pending > 0) {
            token.transfer(msg.sender, pending);
            emit RewardPaid(msg.sender, pending);
        }
        if (amount > 0) {
            user.amount -= amount;
            totalStaked -= amount;
            token.transfer(msg.sender, amount);
            emit Withdrawn(msg.sender, amount);
        }
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e18;
    }

    function pendingReward(address userAddr) external view returns (uint256) {
        StakeInfo storage user = stakes[userAddr];
        uint256 _accRewardPerShare = accRewardPerShare;
        if (block.timestamp > lastRewardTime && totalStaked != 0) {
            uint256 elapsed = block.timestamp - lastRewardTime;
            uint256 reward = elapsed * rewardPerSecond;
            _accRewardPerShare += (reward * 1e18) / totalStaked;
        }
        return (user.amount * _accRewardPerShare) / 1e18 - user.rewardDebt;
    }

    function setRewardPerSecond(uint256 _rewardPerSecond) external onlyOwner {
        updatePool();
        rewardPerSecond = _rewardPerSecond;
    }
}
