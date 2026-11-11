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

    // ---------------------------------------------------------------------
    // Airdrop
    // ---------------------------------------------------------------------
    function airdrop(address[] memory recipients, uint256[] memory amounts) external onlyRole(AIRDROP_ROLE) {
        require(recipients.length == amounts.length, "MOP: arrays length mismatch");
        uint256 total = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            total += amounts[i];
        }
        require(totalSupply() + total <= maxSupply, "MOP: airdrop exceeds max supply");

        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "MOP: zero address");
            require(amounts[i] > 0, "MOP: zero amount");
            _mint(recipients[i], amounts[i]);
            emit Airdrop(recipients[i], amounts[i]);
        }
    }

    // ---------------------------------------------------------------------
    // Batch transfer
    // ---------------------------------------------------------------------
    function batchTransfer(address[] memory recipients, uint256[] memory amounts) external {
        require(recipients.length == amounts.length, "MOP: arrays length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "MOP: zero address");
            require(amounts[i] > 0, "MOP: zero amount");
            _transfer(msg.sender, recipients[i], amounts[i]);
        }
        emit BatchTransfer(msg.sender, recipients, amounts);
    }

    // ---------------------------------------------------------------------
    // Override _transfer to enforce pause on transfer
    // ---------------------------------------------------------------------
    function _transfer(address from, address to, uint256 value) internal override(ERC20Upgradeable, ERC20SnapshotUpgradeable) whenNotPaused {
        super._transfer(from, to, value);
    }

    // ---------------------------------------------------------------------
    // UUPS upgradeability
    // ---------------------------------------------------------------------
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}

/**
 * @title MagnumOpusNFT
 * @dev ERC721 with enumerable, URI storage, ERC2981 royalties, lazy minting, batch mint, pausable and upgradeable.
 */
contract MagnumOpusNFT is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    ERC2981Upgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ROYALTY_MANAGER_ROLE = keccak256("ROYALTY_MANAGER_ROLE");

    // Lazy minting: signer can sign token mint requests
    bytes32 public constant LAZY_MINT_ROLE = keccak256("LAZY_MINT_ROLE");

    // Maximum supply cap (optional)
    uint256 public maxSupply;

    // Base URI for token metadata
    string public baseURI;

    // Royalty defaults (in basis points, 1000 = 10%)
    uint256 public defaultRoyaltyBps;

    // Events
    event BatchMint(address indexed minter, uint256[] tokenIds, string[] uris);
    event LazyMint(address indexed signer, uint256 indexed tokenId, string uri, uint256 expires);
    event MaxSupplyUpdated(uint256 newMaxSupply);
    event BaseURIUpdated(string newBaseURI);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(
        string memory _name,
        string memory _symbol,
        string memory _baseURI,
        uint256 _maxSupply,
        uint256 _defaultRoyaltyBps
    ) public initializer {
        __ERC721_init(_name, _symbol);
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ERC2981_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        require(_maxSupply > 0, "NFT: max supply must be > 0");
        require(_defaultRoyaltyBps <= 10000, "NFT: royalty bps > 100%");

        maxSupply = _maxSupply;
        defaultRoyaltyBps = _defaultRoyaltyBps;
        baseURI = _baseURI;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(ROYALTY_MANAGER_ROLE, msg.sender);
        _grantRole(LAZY_MINT_ROLE, msg.sender);
    }

    // ---------------------------------------------------------------------
    // Core ERC721 overrides
    // ---------------------------------------------------------------------
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _afterTokenTransfer(address from, address to, uint256 tokenId) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._afterTokenTransfer(from, to, tokenId);
    }

    // ---------------------------------------------------------------------
    // Minting
    // ---------------------------------------------------------------------
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) nonReentrant {
        uint256 supply = totalSupply();
        require(supply + amount <= maxSupply, "NFT: exceeds max supply");
        require(amount > 0, "NFT: amount must be > 0");

        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = supply + i + 1;
            _mint(to, tokenId);
        }
    }

    function batchMint(address to, uint256[] memory tokenIds, string[] memory uris) external onlyRole(MINTER_ROLE) nonReentrant {
        require(tokenIds.length == uris.length, "NFT: arrays length mismatch");
        require(tokenIds.length > 0, "NFT: empty batch");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(tokenIds[i] > 0 && tokenIds[i] <= maxSupply, "NFT: invalid tokenId");
            _mint(to, tokenIds[i]);
            _setTokenURI(tokenIds[i], uris[i]);
        }

        emit BatchMint(to, tokenIds, uris);
    }

    // ---------------------------------------------------------------------
    // Lazy minting with EIP-712 signature
    // ---------------------------------------------------------------------
    struct LazyMintData {
        address signer;
        uint256 tokenId;
        string uri;
        uint256 expires;
    }

    function lazyMint(LazyMintData calldata data, bytes memory signature) external nonReentrant {
        require(data.signer != address(0), "NFT: invalid signer");
        require(block.timestamp <= data.expires, "NFT: signature expired");
        require(_isValidSignature(data, signature), "NFT: invalid signature");

        // Check that signer has LAZY_MINT_ROLE
        require(hasRole(LAZY_MINT_ROLE, data.signer), "NFT: signer lacks role");

        // Mint to signer or specified address? For simplicity, mint to signer
        _mint(data.signer, data.tokenId);
        _setTokenURI(data.tokenId, data.uri);

        emit LazyMint(data.signer, data.tokenId, data.uri, data.expires);
    }

    function _isValidSignature(LazyMintData calldata data, bytes memory signature) internal view returns (bool) {
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(data)));
        return digest.recover(signature) == data.signer;
    }

    // ---------------------------------------------------------------------
    // Pausing
    // ---------------------------------------------------------------------
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ---------------------------------------------------------------------
    // Royalty management
    // ---------------------------------------------------------------------
    function setDefaultRoyalty(uint256 royaltyBps) external onlyRole(ROYALTY_MANAGER_ROLE) {
        require(royaltyBps <= 10000, "NFT: royalty bps > 100%");
        defaultRoyaltyBps = royaltyBps;
    }

    function setTokenRoyalty(uint256 tokenId, address recipient, uint256 royaltyBps) external onlyRole(ROYALTY_MANAGER_ROLE) {
        require(royaltyBps <= 10000, "NFT: royalty bps > 100%");
        _setTokenRoyalty(tokenId, recipient, royaltyBps);
    }

    function resetTokenRoyalty(uint256 tokenId) external onlyRole(ROYALTY_MANAGER_ROLE) {
        _resetTokenRoyalty(tokenId);
    }

    // Override ERC2981 to use default royalty
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view override returns (address, uint256) {
        (address recipient, uint256 royaltyAmount) = super.royaltyInfo(tokenId, salePrice);
        if (recipient == address(0) && defaultRoyaltyBps > 0 && salePrice > 0) {
            // Use default royalty if no specific royalty set
            uint256 defaultRoyalty = (salePrice * defaultRoyaltyBps) / 10000;
            // We need to know who the default recipient is - use contract owner or a stored default
            // For simplicity, use the admin role holder
            address defaultRecipient = getRoleMember(DEFAULT_ADMIN_ROLE, 0);
            return (defaultRecipient, defaultRoyalty);
        }
        return (recipient, royaltyAmount);
    }

    // ---------------------------------------------------------------------
    // Admin functions
    // ---------------------------------------------------------------------
    function setMaxSupply(uint256 newMaxSupply) external onlyRole(ADMIN_ROLE) {
        require(newMaxSupply >= totalSupply(), "NFT: new max < totalSupply");
        maxSupply = newMaxSupply;
        emit MaxSupplyUpdated(newMaxSupply);
    }

    function setBaseURI(string memory _newBaseURI) external onlyRole(ADMIN_ROLE) {
        baseURI = _newBaseURI;
        emit BaseURIUpdated(_newBaseURI);
    }

    // ---------------------------------------------------------------------
    // UUPS upgradeability
    // ---------------------------------------------------------------------
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    // ---------------------------------------------------------------------
    // ERC721 overrides for enumerable support
    // ---------------------------------------------------------------------
    function _ownerOf(uint256 tokenId) internal view override(ERC721Upgradeable, ERC721EnumerableUpgradeable) returns (address) {
        return super._ownerOf(tokenId);
    }

    function _exists(uint256 tokenId) internal view override(ERC721Upgradeable, ERC721EnumerableUpgradeable) returns (bool) {
        return super._exists(tokenId);
    }
}
