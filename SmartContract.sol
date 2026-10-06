// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MagnumOpusToken is ERC20, Ownable {
    using SafeMath for uint256;

    uint256 private constant INITIAL_SUPPLY = 1_000_000_000 * 10**18;
    uint256 private constant MAX_SUPPLY = 10_000_000_000 * 10**18;
    uint256 private constant TOKEN_DECIMALS = 18;

    address public stakingContract;
    address public liquidityPool;

    event TokenStaked(address indexed user, uint256 amount);
    event TokenUnstaked(address indexed user, uint256 amount);
    event LiquidityAdded(address indexed user, uint256 amount);
    event LiquidityRemoved(address indexed user, uint256 amount);

    constructor() ERC20("MagnumOpusToken", "MOT") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    modifier onlyStakingContract() {
        require(msg.sender == stakingContract, "Only staking contract can call this function");
        _;
    }

    modifier onlyLiquidityPool() {
        require(msg.sender == liquidityPool, "Only liquidity pool can call this function");
        _;
    }

    function setStakingContract(address _stakingContract) external onlyOwner {
        stakingContract = _stakingContract;
    }

    function setLiquidityPool(address _liquidityPool) external onlyOwner {
        liquidityPool = _liquidityPool;
    }

    function stake(uint256 amount) external onlyStakingContract {
        _burn(msg.sender, amount);
        emit TokenStaked(msg.sender, amount);
    }

    function unstake(uint256 amount) external onlyStakingContract {
        _mint(msg.sender, amount);
        emit TokenUnstaked(msg.sender, amount);
    }

    function addLiquidity(uint256 amount) external onlyLiquidityPool {
        _burn(msg.sender, amount);
        emit LiquidityAdded(msg.sender, amount);
    }

    function removeLiquidity(uint256 amount) external onlyLiquidityPool {
        _mint(msg.sender, amount);
        emit LiquidityRemoved(msg.sender, amount);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        require(totalSupply().add(amount) <= MAX_SUPPLY, "Exceeds maximum supply");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function decimals() public pure override returns (uint8) {
        return TOKEN_DECIMALS;
    }
}