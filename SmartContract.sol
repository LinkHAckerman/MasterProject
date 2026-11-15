// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * Magnum Opus – Unified Token & NFT Suite
 * -------------------------------------------------
 * This file contains two upgradeable contracts:
 *   1. MagnumOpusToken   – ERC20 with snapshot, permit, burn, pausable, role–based minting, airdrop and batch transfer.
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
 * @dev ERC20 token with upgradeability, snapshot, permit, role–based minting, airdrop, batch transfer and pausable controls.
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
    // Access–controlled functions
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

    // ---------------------------------------------------------------------
    // Airdrop and batch transfer functions
    // ---------------------------------------------------------------------
    function airdrop(address[] calldata recipients, uint256[] calldata amounts) external onlyRole(AIRDROP_ROLE) {
        require(recipients.length == amounts.length, "MOP: recipients and amounts length mismatch");
        require(totalSupply() + amounts.reduce((x, y) => x + y) <= maxSupply, "MOP: exceeds max supply");

        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
            emit Airdrop(recipients[i], amounts[i]);
        }
    }

    function batchTransfer(address[] calldata recipients, uint256[] calldata amounts) external {
        require(recipients.length == amounts.length, "MOP: recipients and amounts length mismatch");
        uint256 totalAmount = amounts.reduce((x, y) => x + y);
        require(balanceOf(msg.sender) >= totalAmount, "MOP: insufficient balance");

        for (uint256 i = 0; i < recipients.length; i++) {
            _transfer(msg.sender, recipients[i], amounts[i]);
        }
        emit BatchTransfer(msg.sender, recipients, amounts);
    }

    // ---------------------------------------------------------------------
    // UUPS Upgradeability
    // ---------------------------------------------------------------------
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    function upgradeTo(address newImplementation) external onlyRole(ADMIN_ROLE) {
        _upgradeTo(newImplementation);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) external onlyRole(ADMIN_ROLE) {
        _upgradeToAndCall(newImplementation, data);
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
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ROYALTY_ROLE = keccak256("ROYALTY_ROLE");

    // Events
    event RoyaltyUpdated(uint256 feeNumerator);
    event BatchMint(address indexed to, uint256[] tokenIds, string[] tokenURIs);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(string memory name, string memory symbol, uint256 feeNumerator) public initializer {
        __ERC721_init(name, symbol);
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ERC2981_init(feeNumerator);
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(ROYALTY_ROLE, msg.sender);
    }

    // ---------------------------------------------------------------------
    // Core ERC721 overrides
    // ---------------------------------------------------------------------
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override(ERC721Upgradeable, ERC2981Upgradeable) whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    // ---------------------------------------------------------------------
    // Access–controlled functions
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

    function updateRoyalty(uint256 feeNumerator) external onlyRole(ROYALTY_ROLE) {
        _setDefaultRoyalty(msg.sender, feeNumerator);
        emit RoyaltyUpdated(feeNumerator);
    }

    // ---------------------------------------------------------------------
    // Lazy minting and batch minting functions
    // ---------------------------------------------------------------------
    function lazyMint(address to, uint256 tokenId, string memory tokenURI) external onlyRole(MINTER_ROLE) {
        require(!_exists(tokenId), "MOP: token already exists");
        _mint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
    }

    function batchMint(address to, uint256[] calldata tokenIds, string[] calldata tokenURIs) external onlyRole(MINTER_ROLE) {
        require(tokenIds.length == tokenURIs.length, "MOP: tokenIds and tokenURIs length mismatch");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(!_exists(tokenIds[i]), "MOP: token already exists");
            _mint(to, tokenIds[i]);
            _setTokenURI(tokenIds[i], tokenURIs[i]);
        }
        emit BatchMint(to, tokenIds, tokenURIs);
    }

    // ---------------------------------------------------------------------
    // UUPS Upgradeability
    // ---------------------------------------------------------------------
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    function upgradeTo(address newImplementation) external onlyRole(ADMIN_ROLE) {
        _upgradeTo(newImplementation);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) external onlyRole(ADMIN_ROLE) {
        _upgradeToAndCall(newImplementation, data);
    }
}