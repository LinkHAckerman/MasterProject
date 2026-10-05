// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MagnumOpusToken is ERC20, Ownable {
    using SafeMath for uint256;

    uint256 private constant INITIAL_SUPPLY = 1_000_000_000 * (10 ** decimals());
    uint256 private _totalSupply;

    event TokenMinted(address indexed to, uint256 amount);
    event TokenBurned(address indexed from, uint256 amount);

    constructor() ERC20("MagnumOpusToken", "MOT") {
        _mint(msg.sender, INITIAL_SUPPLY);
        _totalSupply = INITIAL_SUPPLY;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        require(amount > 0, "Mint amount must be greater than 0");
        _mint(to, amount);
        _totalSupply = _totalSupply.add(amount);
        emit TokenMinted(to, amount);
    }

    function burn(uint256 amount) public {
        require(amount > 0, "Burn amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _burn(msg.sender, amount);
        _totalSupply = _totalSupply.sub(amount);
        emit TokenBurned(msg.sender, amount);
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        require(to != address(0), "Invalid recipient address");
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        require(to != address(0), "Invalid recipient address");
        _transfer(from, to, amount);
        _approve(
            from,
            msg.sender,
            allowance(from, msg.sender).sub(amount, "Insufficient allowance")
        );
        return true;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(
            msg.sender,
            spender,
            allowance(msg.sender, spender).add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        require(currentAllowance >= subtractedValue, "Insufficient allowance");
        _approve(
            msg.sender,
            spender,
            currentAllowance.sub(subtractedValue)
        );
        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "Invalid sender address");
        require(to != address(0), "Invalid recipient address");
        require(balanceOf(from) >= amount, "Insufficient balance");

        _beforeTokenTransfer(from, to, amount);
        super._transfer(from, to, amount);
        emit Transfer(from, to, amount);
        _afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal virtual {
        require(to != address(0), "Invalid recipient address");
        _beforeTokenTransfer(address(0), to, amount);
        super._mint(to, amount);
        emit Transfer(address(0), to, amount);
        _afterTokenTransfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        require(from != address(0), "Invalid sender address");
        _beforeTokenTransfer(from, address(0), amount);
        super._burn(from, amount);
        emit Transfer(from, address(0), amount);
        _afterTokenTransfer(from, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "Invalid owner address");
        require(spender != address(0), "Invalid spender address");
        _approve(owner, spender, amount);
        emit Approval(owner, spender, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}