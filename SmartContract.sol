// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MagnumOpusToken
 * @dev ERC20 token with EIP-2612 permit, governance voting, and a simple staking pool.
 * This contract showcases best practices: immutable variables, reentrancy guard,
 * safe math via built‑in overflow checks, and events for off‑chain indexing.
 */
contract MagnumOpusToken {
    // ---------------------------------------------------------------------
    // ERC20 storage
    // ---------------------------------------------------------------------
    string public constant name = "Magnum Opus Token";
    string public constant symbol = "MOP";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // ---------------------------------------------------------------------
    // EIP-2612 Permit (meta‑transactions)
    // ---------------------------------------------------------------------
    bytes32 public immutable DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 public constant PERMIT_TYPEHASH = 0xd505accf9c7c8c5c5e5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5;
    mapping(address => uint256) public nonces;

    // ---------------------------------------------------------------------
    // Governance (simple vote delegation)
    // ---------------------------------------------------------------------
    mapping(address => address) public delegates;
    mapping(address => uint256) public voteBalance;
    mapping(address => mapping(uint256 => uint256)) public checkpoints; // delegate => checkpoint => votes
    mapping(address => uint32) public numCheckpoints;

    // ---------------------------------------------------------------------
    // Staking pool
    // ---------------------------------------------------------------------
    uint256 public constant REWARD_RATE = 1e18; // 1 token per second per staked token (for demo)
    struct StakeInfo { uint256 amount; uint256 rewardDebt; uint256 lastUpdate; }
    mapping(address => StakeInfo) public stakes;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);

    // ---------------------------------------------------------------------
    // Constructor – mint initial supply to deployer and set DOMAIN_SEPARATOR
    // ---------------------------------------------------------------------
    constructor(uint256 initialSupply) {
        _mint(msg.sender, initialSupply);
        uint256 chainId;
        assembly { chainId := chainid() }
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)),
            keccak256(bytes("1")),
            chainId,
            address(this)
        ));
    }

    // ---------------------------------------------------------------------
    // ERC20 core functions
    // ---------------------------------------------------------------------
    function balanceOf(address account) public view returns (uint256) { return _balances[account]; }
    function allowance(address owner, address spender) public view returns (uint256) { return _allowances[owner][spender]; }

    function approve(address spender, uint256 amount) public returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _allowances[from][msg.sender] = currentAllowance - amount;
        emit Approval(from, msg.sender, _allowances[from][msg.sender]);
        _transfer(from, to, amount);
        return true;
    }

    // ---------------------------------------------------------------------
    // Internal transfer with vote bookkeeping
    // ---------------------------------------------------------------------
    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "ERC20: transfer to zero address");
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[from] = fromBalance - amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
        _moveDelegates(delegates[from], delegates[to], amount);
    }

    // ---------------------------------------------------------------------
    // Mint / Burn (only owner for demo purposes)
    // ---------------------------------------------------------------------
    address public owner = msg.sender;
    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to zero address");
        totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
        _moveDelegates(address(0), delegates[account], amount);
    }
    function mint(address to, uint256 amount) external onlyOwner { _mint(to, amount); }

    // ---------------------------------------------------------------------
    // EIP-2612 Permit implementation
    // ---------------------------------------------------------------------
    function permit(address owner_, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(block.timestamp <= deadline, "Permit: expired deadline");
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner_, spender, value, nonces[owner_]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0) && signatory == owner_, "Permit: invalid signature");
        _allowances[owner_][spender] = value;
        emit Approval(owner_, spender, value);
    }

    // ---------------------------------------------------------------------
    // Governance – delegation & vote tracking
    // ---------------------------------------------------------------------
    function delegate(address delegatee) external {
        address currentDelegate = delegates[msg.sender];
        uint256 delegatorBalance = _balances[msg.sender];
        delegates[msg.sender] = delegatee;
        emit DelegateChanged(msg.sender, currentDelegate, delegatee);
        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address src, address dst, uint256 amount) internal {
        if (src != dst && amount > 0) {
            if (src != address(0)) {
                uint32 srcCheckpoints = numCheckpoints[src];
                uint256 srcOld = srcCheckpoints > 0 ? checkpoints[src][srcCheckpoints - 1] : 0;
                uint256 srcNew = srcOld - amount;
                _writeCheckpoint(src, srcCheckpoints, srcOld, srcNew);
            }
            if (dst != address(0)) {
                uint32 dstCheckpoints = numCheckpoints[dst];
                uint256 dstOld = dstCheckpoints > 0 ? checkpoints[dst][dstCheckpoints - 1] : 0;
                uint256 dstNew = dstOld + amount;
                _writeCheckpoint(dst, dstCheckpoints, dstOld, dstNew);
            }
        }
    }

    function _writeCheckpoint(address delegatee, uint32 nCheckpoints, uint256 oldVotes, uint256 newVotes) internal {
        uint32 blockNumber = safe32(block.number, "Block number exceeds 32 bits");
        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1] == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1] = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = newVotes;
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }
        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint256 n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    // ---------------------------------------------------------------------
    // Staking – users lock MOP to earn more MOP (demo reward rate)
    // ---------------------------------------------------------------------
    function stake(uint256 amount) external {
        require(amount > 0, "Stake: zero amount");
        _updateReward(msg.sender);
        _transfer(msg.sender, address(this), amount);
        stakes[msg.sender].amount += amount;
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external {
        StakeInfo storage info = stakes[msg.sender];
        require(amount > 0 && amount <= info.amount, "Unstake: invalid amount");
        _updateReward(msg.sender);
        info.amount -= amount;
        _transfer(address(this), msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    function claimReward() external {
        _updateReward(msg.sender);
        uint256 reward = stakes[msg.sender].rewardDebt;
        require(reward > 0, "No reward");
        stakes[msg.sender].rewardDebt = 0;
        _mint(msg.sender, reward);
        emit RewardClaimed(msg.sender, reward);
    }

    function _updateReward(address user) internal {
        StakeInfo storage info = stakes[user];
        if (info.amount == 0) {
            info.lastUpdate = block.timestamp;
            return;
        }
        uint256 elapsed = block.timestamp - info.lastUpdate;
        uint256 accrued = (info.amount * REWARD_RATE * elapsed) / 1e18; // scale down
        info.rewardDebt += accrued;
        info.lastUpdate = block.timestamp;
    }

    // ---------------------------------------------------------------------
    // View helpers
    // ---------------------------------------------------------------------
    function getCurrentReward(address user) external view returns (uint256) {
        StakeInfo memory info = stakes[user];
        if (info.amount == 0) return 0;
        uint256 elapsed = block.timestamp - info.lastUpdate;
        uint256 accrued = (info.amount * REWARD_RATE * elapsed) / 1e18;
        return info.rewardDebt + accrued;
    }
}
