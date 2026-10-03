// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MAGNUM OPUS // Cryptographic Ecosystem & DeFi Hub
 * @notice The absolute pinnacle of Solidity engineering: An all-in-one DeFi Hub
 *         combining a custom ERC20 (OPUS) with transaction taxes, an ERC721 (OPUSART)
 *         generating fully on-chain glowing neon SVG vector metadata, a dynamic constant-product
 *         AMM engine, and a global multi-staker rewards vault calculated in O(1) complexity.
 */

library Strings {
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}

library Base64 {
    string internal constant TABLE_ENCODE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    function encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        string memory table = TABLE_ENCODE;
        string memory result = new string(4 * ((data.length + 2) / 3));

        assembly {
            let tablePtr := add(table, 1)
            let resultPtr := add(result, 32)
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))

            for {} lt(dataPtr, endPtr) {} {
                let input := 0
                let length := 0
                
                if lt(dataPtr, endPtr) {
                    input := shl(16, byte(0, mload(dataPtr)))
                    dataPtr := add(dataPtr, 1)
                    length := add(length, 1)
                }
                if lt(dataPtr, endPtr) {
                    input := or(input, shl(8, byte(0, mload(dataPtr))))
                    dataPtr := add(dataPtr, 1)
                    length := add(length, 1)
                }
                if lt(dataPtr, endPtr) {
                    input := or(input, byte(0, mload(dataPtr)))
                    dataPtr := add(dataPtr, 1)
                    length := add(length, 1)
                }

                mstore8(resultPtr, byte(and(shr(18, input), 0x3F), tablePtr))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, byte(and(shr(12, input), 0x3F), tablePtr))
                resultPtr := add(resultPtr, 1)
                
                switch length
                case 1 {
                    mstore8(resultPtr, 0x3D)
                    resultPtr := add(resultPtr, 1)
                    mstore8(resultPtr, 0x3D)
                    resultPtr := add(resultPtr, 1)
                }
                case 2 {
                    mstore8(resultPtr, byte(and(shr(6, input), 0x3F), tablePtr))
                    resultPtr := add(resultPtr, 1)
                    mstore8(resultPtr, 0x3D)
                    resultPtr := add(resultPtr, 1)
                }
                default {
                    mstore8(resultPtr, byte(and(shr(6, input), 0x3F), tablePtr))
                    resultPtr := add(resultPtr, 1)
                    mstore8(resultPtr, byte(and(input, 0x3F), tablePtr))
                    resultPtr := add(resultPtr, 1)
                }
            }
        }
        return result;
    }
}

contract OPUSToken {
    string public constant name = "Magnum Opus Utility Token";
    string public constant symbol = "OPUS";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public owner;
    address public defiHub;
    
    mapping(address => bool) public isFeeExcluded;

    uint256 public buyFeePercent = 2;
    uint256 public sellFeePercent = 4;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event FeeExcluded(address indexed account, bool isExcluded);
    event FeesUpdated(uint256 buyFee, uint256 sellFee);

    modifier onlyOwner() {
        require(msg.sender == owner, "OPUS: Caller is not the owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        isFeeExcluded[msg.sender] = true;
        isFeeExcluded[address(this)] = true;
    }

    function setDefiHub(address _defiHub) external onlyOwner {
        require(_defiHub != address(0), "OPUS: Invalid hub address");
        defiHub = _defiHub;
        isFeeExcluded[_defiHub] = true;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner || msg.sender == defiHub, "OPUS: Unauthorized mint");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(balanceOf[from] >= amount, "OPUS: Burn amount exceeds balance");
        if (msg.sender != from) {
            require(allowance[from][msg.sender] >= amount, "OPUS: Burn amount exceeds allowance");
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function setExcludedFromFees(address account, bool excluded) external onlyOwner {
        isFeeExcluded[account] = excluded;
        emit FeeExcluded(account, excluded);
    }

    function updateFees(uint256 newBuyFee, uint256 newSellFee) external onlyOwner {
        require(newBuyFee <= 10 && newSellFee <= 10, "OPUS: Fees cannot exceed 10%");
        buyFeePercent = newBuyFee;
        sellFeePercent = newSellFee;
        emit FeesUpdated(newBuyFee, newSellFee);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "OPUS: Transfer exceeds allowance");
        allowance[from][msg.sender] -= amount;
        return _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(from != address(0), "OPUS: Transfer from zero address");
        require(to != address(0), "OPUS: Transfer to zero address");
        require(balanceOf[from] >= amount, "OPUS: Transfer exceeds balance");

        uint256 feeAmount = 0;

        if (defiHub != address(0) && !isFeeExcluded[from] && !isFeeExcluded[to]) {
            if (to == defiHub) {
                feeAmount = (amount * sellFeePercent) / 100;
            } else if (from == defiHub) {
                feeAmount = (amount * buyFeePercent) / 100;
            }
        }

        uint256 sendAmount = amount - feeAmount;

        balanceOf[from] -= amount;
        balanceOf[to] += sendAmount;
        emit Transfer(from, to, sendAmount);

        if (feeAmount > 0) {
            balanceOf[defiHub] += feeAmount;
            emit Transfer(from, defiHub, feeAmount);
            MagnumOpusDeFiHub(payable(defiHub)).notifyFeeReceived(feeAmount);
        }

        return true;
    }
}

contract OPUSNFT {
    using Strings for uint256;

    string public constant name = "Magnum Opus Artifacts";
    string public constant symbol = "OPUSART";
    
    uint256 public nextTokenId;
    address public owner;
    address public defiHub;

    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    modifier onlyOwner() {
        require(msg.sender == owner, "NFT: Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        nextTokenId = 1;
    }

    function setDefiHub(address _defiHub) external onlyOwner {
        defiHub = _defiHub;
    }

    function mint(address to) external returns (uint256) {
        require(msg.sender == owner || msg.sender == defiHub, "NFT: Unauthorized mint");
        uint256 tokenId = nextTokenId;
        nextTokenId++;

        balanceOf[to]++;
        ownerOf[tokenId] = to;

        emit Transfer(address(0), to, tokenId);
        return tokenId;
    }

    function approve(address to, uint256 tokenId) external {
        address tokenOwner = ownerOf[tokenId];
        require(msg.sender == tokenOwner || isApprovedForAll[tokenOwner][msg.sender], "NFT: Not authorized");
        getApproved[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(ownerOf[tokenId] == from, "NFT: Incorrect owner");
        require(to != address(0), "NFT: Zero address destination");
        
        address spender = msg.sender;
        require(
            spender == from || 
            getApproved[tokenId] == spender || 
            isApprovedForAll[from][spender],
            "NFT: Not authorized spender"
        );

        getApproved[tokenId] = address(0);
        balanceOf[from]--;
        balanceOf[to]++;
        ownerOf[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
        transferFrom(from, to, tokenId);
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(ownerOf[tokenId] != address(0), "NFT: URI query for nonexistent token");
        
        string memory tokenIdStr = tokenId.toString();
        string memory ownerAddrStr = _addressToString(ownerOf[tokenId]);
        
        string memory svg = string(
            abi.encodePacked(
                "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 500 500' width='100%' height='100%'>",
                "<defs>",
                "<linearGradient id='skyGrad' x1='0%' y1='0%' x2='100%' y2='100%'>",
                "<stop offset='0%' stop-color='#080c1e'/>",
                "<stop offset='100%' stop-color='#030611'/>",
                "</linearGradient>",
                "<linearGradient id='glowGrad' x1='0%' y1='0%' x2='100%' y2='100%'>",
                "<stop offset='0%' stop-color='#38bdf8'/>",
                "<stop offset='100%' stop-color='#a855f7'/>",
                "</linearGradient>",
                "<filter id='glow' x='-20%' y='-20%' width='140%' height='140%'>",
                "<feGaussianBlur stdDeviation='8' result='blur'/>",
                "<feComposite in='SourceGraphic' in2='blur' operator='over'/>",
                "</filter>",
                "</defs>",
                "<rect width='500' height='500' fill='url(#skyGrad)'/>",
                "<g filter='url(#glow)'>",
                "<circle cx='250' cy='220' r='100' fill='none' stroke='url(#glowGrad)' stroke-width='3' stroke-dasharray='10 5'/>",
                "<circle cx='250' cy='220' r='80' fill='none' stroke='#10b981' stroke-width='1' stroke-dasharray='5 20'/>",
                "</g>",
                "<text x='250' y='225' font-family='monospace' font-size='26' font-weight='bold' fill='#f8fafc' text-anchor='middle' letter-spacing='2'>OPUS</text>",
                "<text x='250' y='250' font-family='monospace' font-size='12' fill='#94a3b8' text-anchor='middle'>ARTIFACT #", tokenIdStr, "</text>",
                "<rect x='50' y='360' width='400' height='80' rx='10' fill='rgba(10,15,36,0.8)' stroke='rgba(56,189,248,0.3)' stroke-width='1.5'/>",
                "<text x='70' y='390' font-family='monospace' font-size='12' fill='#38bdf8'>OWNER DISPATCHED:</text>",
                "<text x='70' y='415' font-family='monospace' font-size='10' fill='#f43f5e'>", ownerAddrStr, "</text>",
                "<circle cx='415' cy='400' r='8' fill='#10b981' filter='url(#glow)'/>",
                "</svg>"
            )
        );

        string memory json = Base64.encode(
            bytes(
                abi.encodePacked(
                    '{"name": "Opus Artifact #', tokenIdStr, '", ',
                    '"description": "High-Tech Cryptographic Key Artifact issued by the Magnum Opus Web3 ecosystem.", ',
                    '"image": "data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '", ',
                    '"attributes": [',
                    '{"trait_type": "Class", "value": "On-Chain SVG"},',
                    '{"trait_type": "Security level", "value": "Quantum Hardened"},',
                    '{"trait_type": "Core Generation", "value": "V1"}',
                    ']}'
                )
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function _addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 * i + 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[2 * i + 3] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }
}

contract MagnumOpusDeFiHub {
    OPUSToken public immutable opusToken;
    OPUSNFT public immutable opusNFT;

    address public owner;

    // AMM state reserves
    uint256 public ethReserve;
    uint256 public tokenReserve;
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    // Staking parameters & dynamics
    uint256 public rewardRate; 
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public totalStaked;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public balanceOfStaked;

    // Reentrancy state guard
    uint8 private unlocked = 1;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event TokenSwap(address indexed trader, uint256 ethIn, uint256 tokensOut, uint256 tokensIn, uint256 ethOut);
    event LiquidityAdded(address indexed provider, uint256 ethAmount, uint256 tokenAmount);
    event ArtifactMinted(address indexed user, uint256 tokenId);

    modifier onlyOwner() {
        require(msg.sender == owner, "Hub: Caller is not the owner");
        _;
    }

    modifier nonReentrant() {
        require(unlocked == 1, "Hub: Reentrancy guard triggered");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    constructor(address _tokenAddress, address _nftAddress) {
        owner = msg.sender;
        opusToken = OPUSToken(_tokenAddress);
        opusNFT = OPUSNFT(_nftAddress);
        rewardRate = 1 * 10**16; // 0.01 OPUS tokens base rewards per second
        lastUpdateTime = block.timestamp;
    }

    // --- STAKING CORE ENGINE ---

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (((block.timestamp - lastUpdateTime) * rewardRate * 1e18) / totalStaked);
    }

    function earned(address account) public view returns (uint256) {
        return ((balanceOfStaked[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) + rewards[account];
    }

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Hub: Cannot stake 0");
        totalStaked += amount;
        balanceOfStaked[msg.sender] += amount;
        require(opusToken.transferFrom(msg.sender, address(this), amount), "Hub: Stake transfer failed");
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Hub: Cannot withdraw 0");
        require(balanceOfStaked[msg.sender] >= amount, "Hub: Withdraw amount exceeds stake");
        totalStaked -= amount;
        balanceOfStaked[msg.sender] -= amount;
        require(opusToken.transfer(msg.sender, amount), "Hub: Withdraw transfer failed");
        emit Unstaked(msg.sender, amount);
    }

    function claimReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            opusToken.mint(msg.sender, reward);
            emit RewardClaimed(msg.sender, reward);
        }
    }

    function notifyFeeReceived(uint256 amount) external updateReward(address(0)) {
        require(msg.sender == address(opusToken), "Hub: Only token contract can notify");
        if (totalStaked > 0) {
            rewardPerTokenStored += (amount * 1e18) / totalStaked;
        } else {
            opusToken.burn(address(this), amount);
        }
    }

    // --- HIGH-PERFORMANCE AMM CORE ---

    function initializeLiquidity(uint256 tokenAmount) external payable onlyOwner nonReentrant {
        require(ethReserve == 0 && tokenReserve == 0, "Hub: Liquidity already initialized");
        require(msg.value > 0 && tokenAmount > 0, "Hub: Zero liquidity input");
        require(opusToken.transferFrom(msg.sender, address(this), tokenAmount), "Hub: Liquidity transfer failed");

        ethReserve = msg.value;
        tokenReserve = tokenAmount;

        emit LiquidityAdded(msg.sender, msg.value, tokenAmount);
    }

    function addLiquidity(uint256 tokenMaxAmount) external payable nonReentrant returns (uint256 tokenAmount) {
        require(ethReserve > 0 && tokenReserve > 0, "Hub: AMM not initialized");
        require(msg.value > 0, "Hub: Zero ETH value");

        tokenAmount = (msg.value * tokenReserve) / ethReserve;
        require(tokenAmount <= tokenMaxAmount, "Hub: Exceeds max token allowance");
        require(opusToken.transferFrom(msg.sender, address(this), tokenAmount), "Hub: Token deposit failed");

        ethReserve += msg.value;
        tokenReserve += tokenAmount;

        emit LiquidityAdded(msg.sender, msg.value, tokenAmount);
    }

    function swapEthForTokens() external payable nonReentrant returns (uint256 tokensOut) {
        require(msg.value > 0, "Hub: Zero ETH input");
        require(ethReserve > 0 && tokenReserve > 0, "Hub: Insufficient reserves");

        uint256 ethInWithFee = msg.value * 997;
        uint256 numerator = ethInWithFee * tokenReserve;
        uint256 denominator = (ethReserve * 1000) + ethInWithFee;
        tokensOut = numerator / denominator;

        require(tokensOut > 0 && tokensOut <= tokenReserve, "Hub: Insufficient output amount");

        ethReserve += msg.value;
        tokenReserve -= tokensOut;

        require(opusToken.transfer(msg.sender, tokensOut), "Hub: Swap token transfer failed");
        emit TokenSwap(msg.sender, msg.value, tokensOut, 0, 0);
    }

    function swapTokensForEth(uint256 tokenAmount) external nonReentrant returns (uint256 ethOut) {
        require(tokenAmount > 0, "Hub: Zero token input");
        require(ethReserve > 0 && tokenReserve > 0, "Hub: Insufficient reserves");

        uint256 tokenInWithFee = tokenAmount * 997;
        uint256 numerator = tokenInWithFee * ethReserve;
        uint256 denominator = (tokenReserve * 1000) + tokenInWithFee;
        ethOut = numerator / denominator;

        require(ethOut > 0 && ethOut <= ethReserve, "Hub: Insufficient output amount");
        require(opusToken.transferFrom(msg.sender, address(this), tokenAmount), "Hub: Swap token transfer failed");

        tokenReserve += tokenAmount;
        ethReserve -= ethOut;

        (bool success, ) = payable(msg.sender).call{value: ethOut}("");
        require(success, "Hub: Swap ETH transfer failed");

        emit TokenSwap(msg.sender, 0, 0, tokenAmount, ethOut);
    }

    // --- CRYPTO ARTIFACT KEY MINT ---

    function mintArtifact() external nonReentrant returns (uint256) {
        uint256 mintCost = 500 * 10**18; 
        require(opusToken.balanceOf(msg.sender) >= mintCost, "Hub: Insufficient OPUS balance to mint");

        opusToken.burn(msg.sender, mintCost);
        uint256 tokenId = opusNFT.mint(msg.sender);
        
        emit ArtifactMinted(msg.sender, tokenId);
        return tokenId;
    }

    // --- PARAMETER CONTROL ---

    function setRewardRate(uint256 _newRate) external onlyOwner updateReward(address(0)) {
        rewardRate = _newRate;
    }

    receive() external payable {}
}