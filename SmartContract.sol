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
    // Batch operations
    // ---------------------------------------------------------------------
    function batchTransfer(address[] calldata recipients, uint256[] calldata amounts) external whenNotPaused {
        require(recipients.length == amounts.length, "MOP: length mismatch");
        uint256 total;
        for (uint256 i = 0; i < amounts.length; ++i) {
            total += amounts[i];
        }
        require(balanceOf(msg.sender) >= total, "MOP: insufficient balance");
        for (uint256 i = 0; i < recipients.length; ++i) {
            _transfer(msg.sender, recipients[i], amounts[i]);
        }
        emit BatchTransfer(msg.sender, recipients, amounts);
    }

    // ---------------------------------------------------------------------
    // Airdrop – can be called by AIRDROP_ROLE, uses a signed voucher for gas‑less claim
    // ---------------------------------------------------------------------
    struct AirdropVoucher {
        address recipient;
        uint256 amount;
        uint256 nonce;
        bytes signature;
    }

    mapping(address => uint256) public airdropNonce;

    function claimAirdrop(AirdropVoucher calldata voucher) external whenNotPaused {
        require(voucher.recipient == msg.sender, "MOP: voucher not for caller");
        require(voucher.nonce == airdropNonce[msg.sender] + 1, "MOP: invalid nonce");
        // Recreate the signed message
        bytes32 structHash = keccak256(abi.encodePacked(voucher.recipient, voucher.amount, voucher.nonce));
        bytes32 hash = ECDSAUpgradeable.toEthSignedMessageHash(structHash);
        address signer = ECDSAUpgradeable.recover(hash, voucher.signature);
        require(hasRole(AIRDROP_ROLE, signer), "MOP: invalid signer");
        airdropNonce[msg.sender] = voucher.nonce;
        _mint(msg.sender, voucher.amount);
        emit Airdrop(msg.sender, voucher.amount);
    }

    // ---------------------------------------------------------------------
    // Upgradeability – only ADMIN_ROLE can upgrade
    // ---------------------------------------------------------------------
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    uint256[50] private __gap; // Reserved storage gap for future upgrades
}

/**
 * @title MagnumOpusNFT
 * @dev ERC721 contract with upgradeability, lazy minting, batch mint, royalty support, pausable and reentrancy guard.
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
    using Strings for uint256;

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant URI_SETTER_ROLE = keccak256("URI_SETTER_ROLE");

    // Token settings
    uint256 public maxSupply;
    uint256 public maxBatchMint;
    uint256 private _nextTokenId;
    string private _baseTokenURI;

    // Events
    event NFTMinted(address indexed minter, uint256 indexed tokenId, string tokenURI);
    event BatchMinted(address indexed minter, uint256 startTokenId, uint256 count);
    event BaseURIUpdated(string newBaseURI);
    event RoyaltyInfoUpdated(address receiver, uint96 feeNumerator);
    event FundsWithdrawn(address indexed recipient, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        address royaltyReceiver,
        uint96 royaltyFeeBps,
        uint256 _maxSupply,
        uint256 _maxBatchMint
    ) public initializer {
        __ERC721_init(name_, symbol_);
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ERC2981_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(URI_SETTER_ROLE, msg.sender);

        maxSupply = _maxSupply;
        maxBatchMint = _maxBatchMint;
        _nextTokenId = 1;
        _baseTokenURI = baseURI_;

        _setDefaultRoyalty(royaltyReceiver, royaltyFeeBps);
    }

    // ---------------------------------------------------------------------
    // Core overrides
    // ---------------------------------------------------------------------
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view override(ERC721Upgradeable, ERC721URIStorageUpgradeable) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC2981Upgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // ---------------------------------------------------------------------
    // Minting functions
    // ---------------------------------------------------------------------
    function lazyMint(address to, string calldata tokenURI_) external onlyRole(MINTER_ROLE) whenNotPaused nonReentrant {
        require(_nextTokenId <= maxSupply, "MNFT: max supply reached");
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI_);
        emit NFTMinted(to, tokenId, tokenURI_);
    }

    function batchMint(address to, uint256 count) external onlyRole(MINTER_ROLE) whenNotPaused nonReentrant {
        require(count > 0 && count <= maxBatchMint, "MNFT: invalid batch size");
        require(_nextTokenId + count - 1 <= maxSupply, "MNFT: exceeds max supply");
        uint256 startId = _nextTokenId;
        for (uint256 i = 0; i < count; ++i) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(to, tokenId);
            emit NFTMinted(to, tokenId, "");
        }
        emit BatchMinted(to, startId, count);
    }

    // ---------------------------------------------------------------------
    // Administrative setters
    // ---------------------------------------------------------------------
    function setBaseURI(string calldata newBase) external onlyRole(URI_SETTER_ROLE) {
        _baseTokenURI = newBase;
        emit BaseURIUpdated(newBase);
    }

    function setRoyaltyInfo(address receiver, uint96 feeNumerator) external onlyRole(ADMIN_ROLE) {
        _setDefaultRoyalty(receiver, feeNumerator);
        emit RoyaltyInfoUpdated(receiver, feeNumerator);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ---------------------------------------------------------------------
    // Withdrawal of contract balance (e.g., from sales)
    // ---------------------------------------------------------------------
    function withdraw(address payable recipient) external onlyRole(ADMIN_ROLE) nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "MNFT: no balance");
        (bool success, ) = recipient.call{value: balance}("\");
        require(success, "MNFT: withdraw failed");
        emit FundsWithdrawn(recipient, balance);
    }

    // ---------------------------------------------------------------------
    // Upgradeability – only ADMIN_ROLE can upgrade
    // ---------------------------------------------------------------------
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    // ---------------------------------------------------------------------
    // Internal hooks for ERC721Enumerable & ERC721URIStorage compatibility
    // ---------------------------------------------------------------------
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _burn(uint256 tokenId) internal override(ERC721Upgradeable, ERC721URIStorageUpgradeable) {
        super._burn(tokenId);
    }

    uint256[45] private __gapNFT; // Storage gap for future upgrades
}
