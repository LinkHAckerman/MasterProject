// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Magnum Opus Unified Core Ecosystem Contract
 * @author Lead Principal Software Architect
 * @notice Combines the MOPUS Token (ERC20), Staking Vault, NFT Matrix (ERC721), and Governance Engine
 *         to form the ultimate Web3 & DeFi Nexus Engine backplane.
 */

contract MagnumOwnable {
    address public owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "MagnumOwnable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "MagnumOwnable: new owner is zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

contract MopusToken is MagnumOwnable {
    string public constant name = "Magnum Opus Token";
    string public constant symbol = "MOPUS";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(uint256 initialSupply) {
        _mint(msg.sender, initialSupply * 10**decimals);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(allowance[from][msg.sender] >= value, "MopusToken: transfer amount exceeds allowance");
        allowance[from][msg.sender] -= value;
        _transfer(from, to, value);
        return true;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(from != address(0), "MopusToken: transfer from zero address");
        require(to != address(0), "MopusToken: transfer to zero address");
        require(balanceOf[from] >= value, "MopusToken: transfer amount exceeds balance");

        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    function _mint(address account, uint256 value) internal {
        require(account != address(0), "MopusToken: mint to zero address");
        totalSupply += value;
        balanceOf[account] += value;
        emit Transfer(address(0), account, value);
    }

    function _burn(address account, uint256 value) internal {
        require(account != address(0), "MopusToken: burn from zero address");
        require(balanceOf[account] >= value, "MopusToken: burn amount exceeds balance");

        balanceOf[account] -= value;
        totalSupply -= value;
        emit Transfer(account, address(0), value);
    }
}

contract MopusNFT is MagnumOwnable {
    string public constant name = "Magnum Opus Cyber Matrix";
    string public constant symbol = "MOPUS-NFT";

    uint256 public nextTokenId;
    
    struct NFTMetadata {
        string name;
        string rarity;
        uint256 powerIndex;
        string uri;
    }

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint256 => NFTMetadata) public nftRegistry;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event NFTMinted(address indexed to, uint256 indexed tokenId, string name, string rarity, uint256 powerIndex);

    function balanceOf(address owner) external view returns (uint256) {
        require(owner != address(0), "ERC721: balance query for the zero address");
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: owner query for nonexistent token");
        return owner;
    }

    function getMetadata(uint256 tokenId) external view returns (NFTMetadata memory) {
        require(_owners[tokenId] != address(0), "ERC721: metadata query for nonexistent token");
        return nftRegistry[tokenId];
    }

    function mint(
        address to, 
        string calldata nftName, 
        string calldata rarity, 
        uint256 powerIndex,
        string calldata uri
    ) external onlyOwner returns (uint256) {
        uint256 tokenId = nextTokenId++;
        
        _owners[tokenId] = to;
        _balances[to] += 1;
        
        nftRegistry[tokenId] = NFTMetadata({
            name: nftName,
            rarity: rarity,
            powerIndex: powerIndex,
            uri: uri
        });

        emit Transfer(address(0), to, tokenId);
        emit NFTMinted(to, tokenId, nftName, rarity, powerIndex);
        return tokenId;
    }

    function approve(address to, uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        require(msg.sender == owner || _operatorApprovals[owner][msg.sender], "ERC721: approve caller is not owner nor approved for all");
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        require(_owners[tokenId] != address(0), "ERC721: approved query for nonexistent token");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        require(operator != msg.sender, "ERC721: approve to caller");
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: transfer caller is not owner nor approved");
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        transferFrom(from, to, tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, "ERC721: transfer of token that is not own");
        require(to != address(0), "ERC721: transfer to the zero address");

        _tokenApprovals[tokenId] = address(0);
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || _tokenApprovals[tokenId] == spender || _operatorApprovals[owner][spender]);
    }
}

contract MopusVault is MagnumOwnable {
    MopusToken public immutable mopusToken;
    
    struct Staker {
        uint256 stakedAmount;
        uint256 rewardDebt;
        uint256 lastUpdateTimestamp;
    }

    uint256 public totalStaked;
    uint256 public rewardRatePerSec = 4500000000000000; // 0.0045 MOPUS per sec, matched with app.js
    uint256 public constant ACC_REWARD_PRECISION = 1e12;
    uint256 public accRewardPerShare;
    uint256 public lastRewardTimestamp;

    mapping(address => Staker) public stakers;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);

    constructor(MopusToken _mopusToken) {
        mopusToken = _mopusToken;
        lastRewardTimestamp = block.timestamp;
    }

    function updatePool() public {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }
        if (totalStaked == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 elapsed = block.timestamp - lastRewardTimestamp;
        uint256 rewards = elapsed * rewardRatePerSec;
        accRewardPerShare += (rewards * ACC_REWARD_PRECISION) / totalStaked;
        lastRewardTimestamp = block.timestamp;
    }

    function stake(uint256 amount) external {
        require(amount > 0, "MopusVault: cannot stake 0");
        updatePool();

        Staker storage staker = stakers[msg.sender];
        if (staker.stakedAmount > 0) {
            uint256 pending = ((staker.stakedAmount * accRewardPerShare) / ACC_REWARD_PRECISION) - staker.rewardDebt;
            if (pending > 0) {
                mopusToken.mint(msg.sender, pending);
                emit RewardClaimed(msg.sender, pending);
            }
        }

        mopusToken.transferFrom(msg.sender, address(this), amount);
        staker.stakedAmount += amount;
        totalStaked += amount;
        staker.rewardDebt = (staker.stakedAmount * accRewardPerShare) / ACC_REWARD_PRECISION;
        staker.lastUpdateTimestamp = block.timestamp;

        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        Staker storage staker = stakers[msg.sender];
        require(staker.stakedAmount >= amount, "MopusVault: withdraw amount exceeds stake");
        updatePool();

        uint256 pending = ((staker.stakedAmount * accRewardPerShare) / ACC_REWARD_PRECISION) - staker.rewardDebt;
        if (pending > 0) {
            mopusToken.mint(msg.sender, pending);
            emit RewardClaimed(msg.sender, pending);
        }

        if (amount > 0) {
            staker.stakedAmount -= amount;
            totalStaked -= amount;
            mopusToken.transfer(msg.sender, amount);
            emit Withdrawn(msg.sender, amount);
        }

        staker.rewardDebt = (staker.stakedAmount * accRewardPerShare) / ACC_REWARD_PRECISION;
        staker.lastUpdateTimestamp = block.timestamp;
    }

    function pendingRewards(address user) external view returns (uint256) {
        Staker storage staker = stakers[user];
        uint256 tempAccRewardPerShare = accRewardPerShare;
        if (block.timestamp > lastRewardTimestamp && totalStaked > 0) {
            uint256 elapsed = block.timestamp - lastRewardTimestamp;
            uint256 rewards = elapsed * rewardRatePerSec;
            tempAccRewardPerShare += (rewards * ACC_REWARD_PRECISION) / totalStaked;
        }
        return ((staker.stakedAmount * tempAccRewardPerShare) / ACC_REWARD_PRECISION) - staker.rewardDebt;
    }
}

contract MopusGovernor is MagnumOwnable {
    MopusToken public immutable mopusToken;

    enum VoteType { Against, For, Abstain }
    enum ProposalStatus { Active, Defeated, Passed, Executed }

    struct Proposal {
        uint256 id;
        string title;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 startTime;
        uint256 endTime;
        uint256 quorum;
        bool executed;
        mapping(address => bool) hasVoted;
        mapping(address => VoteType) userVotes;
    }

    uint256 public proposalCount;
    uint256 public constant VOTING_DURATION = 3 days;
    uint256 public constant QUORUM_REQUIRED = 1000000 * 1e18; // 1M votes quorum

    mapping(uint256 => Proposal) public proposals;

    event ProposalCreated(uint256 indexed proposalId, string title, uint256 endTime);
    event Voted(uint256 indexed proposalId, address indexed voter, VoteType voteType, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);

    constructor(MopusToken _mopusToken) {
        mopusToken = _mopusToken;
    }

    function createProposal(string calldata title, string calldata description) external returns (uint256) {
        require(mopusToken.balanceOf(msg.sender) >= 10000 * 1e18, "MopusGovernor: insufficient tokens to propose");

        uint256 proposalId = ++proposalCount;
        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.title = title;
        proposal.description = description;
        proposal.startTime = block.timestamp;
        proposal.endTime = block.timestamp + VOTING_DURATION;
        proposal.quorum = QUORUM_REQUIRED;
        proposal.executed = false;

        emit ProposalCreated(proposalId, title, proposal.endTime);
        return proposalId;
    }

    function castVote(uint256 proposalId, VoteType voteType) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.startTime && block.timestamp <= proposal.endTime, "MopusGovernor: voting is closed");
        require(!proposal.hasVoted[msg.sender], "MopusGovernor: already voted");

        uint256 weight = mopusToken.balanceOf(msg.sender);
        require(weight > 0, "MopusGovernor: zero voting weight");

        if (voteType == VoteType.Against) {
            proposal.againstVotes += weight;
        } else if (voteType == VoteType.For) {
            proposal.forVotes += weight;
        } else {
            proposal.abstainVotes += weight;
        }

        proposal.hasVoted[msg.sender] = true;
        proposal.userVotes[msg.sender] = voteType;

        emit Voted(proposalId, msg.sender, voteType, weight);
    }

    function getProposalStatus(uint256 proposalId) public view returns (ProposalStatus) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.id != 0, "MopusGovernor: proposal does not exist");

        if (proposal.executed) {
            return ProposalStatus.Executed;
        }
        if (block.timestamp <= proposal.endTime) {
            return ProposalStatus.Active;
        }
        
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
        if (totalVotes < proposal.quorum || proposal.forVotes <= proposal.againstVotes) {
            return ProposalStatus.Defeated;
        }
        
        return ProposalStatus.Passed;
    }

    function executeProposal(uint256 proposalId) external {
        ProposalStatus status = getProposalStatus(proposalId);
        require(status == ProposalStatus.Passed, "MopusGovernor: proposal must be Passed to execute");
        
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;

        emit ProposalExecuted(proposalId);
    }

    function getUserVote(uint256 proposalId, address user) external view returns (bool voted, VoteType voteType) {
        Proposal storage proposal = proposals[proposalId];
        return (proposal.hasVoted[user], proposal.userVotes[user]);
    }
}