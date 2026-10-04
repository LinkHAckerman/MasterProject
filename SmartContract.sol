pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MagnumOpusToken is ERC20, Ownable {
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** decimals();
    uint256 private constant MAX_SUPPLY = 2_000_000_000 * 10 ** decimals();

    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    event Burned(address indexed burner, uint256 amount);
    event Minted(address indexed minter, uint256 amount);

    constructor() ERC20("MagnumOpus", "MAGOP") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "MagnumOpusToken: max supply exceeded");
        _mint(to, amount);
        emit Minted(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
        emit Burned(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) public onlyOwner {
        _burn(account, amount);
        emit Burned(account, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (to == DEAD_ADDRESS) {
            _burn(msg.sender, amount);
            emit Burned(msg.sender, amount);
            return true;
        }
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        if (to == DEAD_ADDRESS) {
            _burn(from, amount);
            emit Burned(from, amount);
            return true;
        }
        return super.transferFrom(from, to, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._beforeTokenTransfer(from, to, amount);
        if (from != address(0) && to == DEAD_ADDRESS) {
            revert("MagnumOpusToken: burning not allowed via transfer");
        }
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}