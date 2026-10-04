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
    uint256 private _initialSupply;
    uint256 private _teamAllocation;
    uint256 private _investorAllocation;
    uint256 private _marketingAllocation;
    uint256 private _communityAllocation;

    // Vesting schedule
    uint256 private _vestingDuration;
    uint256 private _vestingStart;
    uint256 private _vestingCliff;

    // Token lockup
    mapping(address => uint256) private _lockedTokens;
    mapping(address => uint256) private _lockupEnd;

    // Events
    event TokenLocked(address indexed holder, uint256 amount, uint256 unlockTime);
    event TokenUnlocked(address indexed holder, uint256 amount);

    // Modifiers
    modifier onlyDuringVesting() {
        require(block.timestamp >= _vestingStart && block.timestamp <= _vestingStart.add(_vestingDuration), "Vesting period not active");
        _;
    }

    modifier onlyAfterVestingCliff() {
        require(block.timestamp >= _vestingStart.add(_vestingCliff), "Vesting cliff not reached");
        _;
    }

    // Constructor
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply,
        uint256 teamAllocation,
        uint256 investorAllocation,
        uint256 marketingAllocation,
        uint256 communityAllocation,
        uint256 vestingDuration,
        uint256 vestingCliff
    ) ERC20(name, symbol) {
        _name = name;
        _symbol = symbol;
        _decimals = decimals;
        _initialSupply = initialSupply;
        _teamAllocation = teamAllocation;
        _investorAllocation = investorAllocation;
        _marketingAllocation = marketingAllocation;
        _communityAllocation = communityAllocation;
        _vestingDuration = vestingDuration;
        _vestingCliff = vestingCliff;
        _vestingStart = block.timestamp;

        _totalSupply = initialSupply;
        _mint(msg.sender, initialSupply);

        // Distribute initial tokens
        _distributeTokens();
    }

    // Distribute tokens to different allocations
    function _distributeTokens() private {
        uint256 teamTokens = _initialSupply.mul(_teamAllocation).div(100);
        uint256 investorTokens = _initialSupply.mul(_investorAllocation).div(100);
        uint256 marketingTokens = _initialSupply.mul(_marketingAllocation).div(100);
        uint256 communityTokens = _initialSupply.mul(_communityAllocation).div(100);

        // Lock tokens for team, investors, and marketing
        _lockTokens(address(0), teamTokens);
        _lockTokens(address(0), investorTokens);
        _lockTokens(address(0), marketingTokens);

        // Transfer community tokens to community address
        _transfer(address(this), address(0), communityTokens);
    }

    // Lock tokens for a specific holder
    function _lockTokens(address holder, uint256 amount) private {
        require(holder != address(0), "Invalid holder address");
        require(amount > 0, "Amount must be greater than 0");

        _lockedTokens[holder] = _lockedTokens[holder].add(amount);
        _lockupEnd[holder] = block.timestamp.add(_vestingDuration);

        emit TokenLocked(holder, amount, _lockupEnd[holder]);
    }

    // Unlock tokens for a specific holder
    function unlockTokens(address holder) public onlyDuringVesting onlyAfterVestingCliff {
        require(holder != address(0), "Invalid holder address");
        require(_lockedTokens[holder] > 0, "No tokens locked");
        require(block.timestamp >= _lockupEnd[holder], "Lockup period not ended");

        uint256 amount = _lockedTokens[holder];
        _lockedTokens[holder] = 0;
        _lockupEnd[holder] = 0;

        _transfer(address(this), holder, amount);

        emit TokenUnlocked(holder, amount);
    }

    // Transfer tokens with additional checks
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        require(sender != address(0), "Invalid sender address");
        require(recipient != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");

        // Check if sender has enough balance
        require(balanceOf(sender) >= amount, "Insufficient balance");

        // Check if sender has locked tokens
        if (_lockedTokens[sender] > 0) {
            require(amount <= balanceOf(sender).sub(_lockedTokens[sender]), "Cannot transfer locked tokens");
        }

        // Perform the transfer
        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(amount);

        emit Transfer(sender, recipient, amount);
    }

    // Get locked tokens for a specific holder
    function getLockedTokens(address holder) external view returns (uint256) {
        return _lockedTokens[holder];
    }

    // Get lockup end time for a specific holder
    function getLockupEnd(address holder) external view returns (uint256) {
        return _lockupEnd[holder];
    }

    // Get vesting information
    function getVestingInfo() external view returns (
        uint256 vestingStart,
        uint256 vestingDuration,
        uint256 vestingCliff
    ) {
        return (_vestingStart, _vestingDuration, _vestingCliff);
    }
}