// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MagnumOpusToken is ERC20, AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() ERC20("Magnum Opus", "MOP") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }
}

contract MagnumOpusNFT is ERC721 {
    using SafeMath for uint256;

    string public name = "Magnum Opus NFT";
    string public symbol = "MNFT";
    uint256 public mintPrice = 1 ether;
    uint256 public maxSupply = 10000;
    uint256 public totalMinted;

    mapping(uint256 => string) private _tokenURIs;

    event Minted(address indexed minter, uint256 indexed tokenId);

    function mint(string memory uri) external payable {
        require(msg.value >= mintPrice, "Insufficient payment");
        require(totalMinted < maxSupply, "Max supply reached");
        totalMinted = totalMinted.add(1);
        uint256 tokenId = totalMinted;
        _mint(msg.sender, tokenId);
        _tokenURIs[tokenId] = uri;
        emit Minted(msg.sender, tokenId);
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        return _tokenURIs[tokenId];
    }
}

contract MagnumOpusDeFi {
    // Simple staking contract
    // ...
}