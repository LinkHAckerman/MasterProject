// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MagnumOpusToken is ERC20, Ownable {
    using SafeMath for uint256;

    // Token parameters
    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 private _totalSupply;

    // Token distribution
    uint256 public constant INITIAL_SUPPLY = 1000000000 * (10 ** 18); // 1 billion tokens
    uint256 public constant TEAM_ALLOCATION = 200000000 * (10 ** 18); // 200 million tokens
    uint256 public constant MARKETING_ALLOCATION = 100000000 * (10 ** 18); // 100 million tokens
    uint256 public constant ECOSYSTEM_ALLOCATION = 300000000 * (10 ** 18); // 300 million tokens
    uint256 public constant COMMUNITY_ALLOCATION = 400000000 * (10 ** 18); // 400 million tokens

    // Token vesting
    uint256 public constant VESTING_PERIOD = 18 months;
    uint256 public constant VESTING_CLIFF = 6 months;
    uint256 public constant VESTING_INTERVAL = 1 month;

    // Token vesting schedule
    struct VestingSchedule {
        uint256 startTime;
        uint256 duration;
        uint256 cliff;
        uint256 interval;
        uint256 amount;
        uint256 released;
        uint256 lastReleaseTime;
    }

    // Token vesting schedules
    mapping(address => VestingSchedule) public vestingSchedules;

    // Token vesting events
    event VestingScheduleCreated(address indexed beneficiary, uint256 amount);
    event TokensReleased(address indexed beneficiary, uint256 amount);

    // Token vesting functions
    function createVestingSchedule(address beneficiary, uint256 amount) public onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        require(vestingSchedules[beneficiary].amount == 0, "Vesting schedule already exists");

        vestingSchedules[beneficiary] = VestingSchedule({
            startTime: block.timestamp,
            duration: VESTING_PERIOD,
            cliff: VESTING_CLIFF,
            interval: VESTING_INTERVAL,
            amount: amount,
            released: 0,
            lastReleaseTime: block.timestamp
        });

        emit VestingScheduleCreated(beneficiary, amount);
    }

    function releaseVestedTokens(address beneficiary) public {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        require(schedule.amount > 0, "No vesting schedule exists");

        uint256 now = block.timestamp;
        uint256 elapsed = now - schedule.startTime;
        uint256 releasable = 0;

        if (elapsed >= schedule.cliff) {
            uint256 intervalsPassed = (elapsed - schedule.cliff) / schedule.interval;
            uint256 totalIntervals = schedule.duration / schedule.interval;
            uint256 vestedAmount = (schedule.amount * intervalsPassed) / totalIntervals;
            releasable = vestedAmount - schedule.released;
        }

        if (releasable > 0) {
            schedule.released += releasable;
            schedule.lastReleaseTime = now;
            _transfer(address(this), beneficiary, releasable);
            emit TokensReleased(beneficiary, releasable);
        }
    }

    // Token distribution functions
    function distributeTokens() public onlyOwner {
        require(_totalSupply == 0, "Tokens already distributed");

        _name = "Magnum Opus Token";
        _symbol = "MOT";
        _decimals = 18;
        _totalSupply = INITIAL_SUPPLY;

        _mint(address(this), _totalSupply);

        // Allocate tokens to team
        _transfer(address(this), msg.sender, TEAM_ALLOCATION);

        // Allocate tokens to marketing
        _transfer(address(this), msg.sender, MARKETING_ALLOCATION);

        // Allocate tokens to ecosystem
        _transfer(address(this), msg.sender, ECOSYSTEM_ALLOCATION);

        // Allocate tokens to community
        _transfer(address(this), msg.sender, COMMUNITY_ALLOCATION);
    }

    // Token functions
    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return super.balanceOf(account);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        return super.transfer(recipient, amount);
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return super.allowance(owner, spender);
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        return super.approve(spender, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        return super.transferFrom(sender, recipient, amount);
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        return super.increaseAllowance(spender, addedValue);
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        return super.decreaseAllowance(spender, subtractedValue);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        super._transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal override {
        require(account != address(0), "ERC20: mint to the zero address");
        _totalSupply = _totalSupply.add(amount);
        super._mint(account, amount);
    }

    function _burn(address account, uint256 amount) internal override {
        require(account != address(0), "ERC20: burn from the zero address");
        _totalSupply = _totalSupply.sub(amount);
        super._burn(account, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal override {
        super._approve(owner, spender, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        super._afterTokenTransfer(from, to, amount);
    }
}