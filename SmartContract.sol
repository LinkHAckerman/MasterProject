// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * Magnum Opus – Unified Token & NFT Suite
 * -------------------------------------------------
 * This file contains two upgradeable contracts:
 *   1. MagnumOpusToken   – ERC20 with snapshot, permit, burn, pausable, role‑based minting, airdrop and batch transfer.
 *   2. MagnumOpusNFT     – ERC721 with enumerable, URI storage, ERC2981 royalties, lazy minting, batch mint, pausable and upgradeable.
 * Both contracts use OpenZeppelin Upgradeable libraries and follow the UUPS proxy pattern.
 */

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20SnapshotUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title MagnumOpusToken
 * @dev ERC20 token with upgradeability, snapshot, permit, role‑based minting, airdrop, batch transfer and pausable controls.
 */
contract MagnumOpusToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20SnapshotUpgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");
    bytes32 public constant AIRDROP_ROLE = keccak256("AIRDROP_ROLE");

    // Immutable cap set at initialization
    uint256 public maxSupply;

    // Events
    event MaxSupplyUpdated(uint256 newMaxSupply);
    event Airdrop(address indexed recipient, uint256 amount);
    event BatchTransfer(address indexed from, address[] recipients, uint256[] amounts);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(uint256 initialSupply, uint256 cap) public initializer {
        __ERC20_init("Magnum Opus", "MOP");
        __ERC20Burnable_init();
        __ERC20Snapshot_init();
        __ERC20Permit_init("Magnum Opus");
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        require(cap >= initialSupply, "MOP: cap must be >= initialSupply");
        maxSupply = cap;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(SNAPSHOT_ROLE, msg.sender);
        _grantRole(AIRDROP_ROLE, msg.sender);

        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply);
        }
    }

    // ---------------------------------------------------------------------
    // Core ERC20 overrides
    // ---------------------------------------------------------------------
    function _update(address from, address to, uint256 value) internal override(ERC20Upgradeable, ERC20SnapshotUpgradeable) whenNotPaused {
        super._update(from, to, value);
    }

    // ---------------------------------------------------------------------
    // Access‑controlled functions
    // ---------------------------------------------------------------------
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(totalSupply() + amount <= maxSupply, "MOP: exceeds max supply");
        _mint(to, amount);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function snapshot() external onlyRole(SNAPSHOT_ROLE) returns (uint256) {
        return _snapshot();
    }

    function updateMaxSupply(uint256 newCap) external onlyRole(ADMIN_ROLE) {
        require(newCap >= totalSupply(), "MOP: new cap < totalSupply");
        maxSupply = newCap;
        emit MaxSupplyUpdated(newCap);
    }

    // New function to handle batch transfers
    function batchTransfer(address[] memory recipients, uint256[] memory amounts) public onlyRole(MINTER_ROLE) {
        require(recipients.length == amounts.length, "MOP: recipients and amounts arrays must be the same length");
        for (uint256 i = 0; i < recipients.length; i++) {
            _transfer(msg.sender, recipients[i], amounts[i]);
        }
        emit BatchTransfer(msg.sender, recipients, amounts);
    }

    // New function to handle airdrops
    function airdrop(address recipient, uint256 amount) public onlyRole(AIRDROP_ROLE) {
        _transfer(msg.sender, recipient, amount);
        emit Airdrop(recipient, amount);
    }
}

/**
 * @title MagnumOpusNFT
 * @dev ERC721 token with upgradeability, enumerable, URI storage, ERC2981 royalties, lazy minting, batch mint, pausable and upgradeable.
 */
contract MagnumOpusNFT is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    ERC2981Upgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Immutable royalty percentage set at initialization
    uint256 public royaltyPercentage;

    // Events
    event RoyaltyUpdated(uint256 newRoyaltyPercentage);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(uint256 initialRoyaltyPercentage) public initializer {
        __ERC721_init("Magnum Opus NFT", "MOPNFT");
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ERC2981_init();
        __ReentrancyGuard_init_unchained();
        __Pausable_init();
        __UUPSUpgradeable_init();

        require(initialRoyaltyPercentage <= 100, "MOPNFT: royalty percentage must be <= 100");
        royaltyPercentage = initialRoyaltyPercentage;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    // ---------------------------------------------------------------------
    // Core ERC721 overrides
    // ---------------------------------------------------------------------
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable) whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    // ---------------------------------------------------------------------
    // Access‑controlled functions
    // ---------------------------------------------------------------------
    function mint(address to, uint256 tokenId, string memory tokenURI) external onlyRole(MINTER_ROLE) {
        _mint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function updateRoyaltyPercentage(uint256 newRoyaltyPercentage) external onlyRole(ADMIN_ROLE) {
        require(newRoyaltyPercentage <= 100, "MOPNFT: royalty percentage must be <= 100");
        royaltyPercentage = newRoyaltyPercentage;
        emit RoyaltyUpdated(newRoyaltyPercentage);
    }
}
