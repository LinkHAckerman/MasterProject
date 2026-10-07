// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";

/**
 * @title MagnumToken
 * @dev ERC20 token with burnable, pausable, permit (EIP-2612) and ownable features.
 */
contract MagnumToken is ERC20, ERC20Burnable, ERC20Pausable, ERC20Permit, Ownable {
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18; // 1M tokens with 18 decimals

    constructor() ERC20("Magnum Token", "MAG") ERC20Permit("Magnum Token") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // The following functions override required hooks from parent contracts
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }
}

/**
 * @title MagnumNFT
 * @dev ERC721 NFT collection with enumerable, URI storage, burnable, pausable and ownable features.
 */
contract MagnumNFT is ERC721, ERC721Enumerable, ERC721URIStorage, ERC721Burnable, ERC721Pausable, Ownable {
    uint256 private _nextTokenId;
    string private _baseTokenURI;

    constructor(string memory baseURI) ERC721("Magnum NFT", "MAGNFT") {
        _baseTokenURI = baseURI;
    }

    /**
     * @dev Mint a new NFT to `to` with optional `tokenURI`.
     * Only the contract owner can call this function.
     */
    function mint(address to, string memory tokenURI) external onlyOwner {
        uint256 tokenId = _nextTokenId;
        _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Override required functions from multiple inheritance
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721, ERC721Enumerable, ERC721Pausable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
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
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Optional: Override baseURI to return a constant prefix.
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
}
