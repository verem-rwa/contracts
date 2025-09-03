// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract PRESALEVEREM is Ownable {
    IERC20 public token;
    IERC20Metadata public tokenMetadata;
    address public sellerAddress;
    address public paymentAddress;
    address public UsdtAddress;
    bool public presaleActive = true;
    bool public whitelistActive = false;
    uint256 public totalSold = 0;

    mapping(address => bool) public whitelist;
    mapping(address => bool) public isPartner;

    uint256 public constant STANDARD_REFERRAL_PERCENT = 5;
    uint256 public constant PARTNER_REFERRAL_PERCENT = 10;

    struct Stage {
        uint256 id;
        uint256 price;
        uint256 maxTokens;
        uint256 tokensSold;
        bool active;
    }

    struct SaleRecord {
        uint256 stageId;
        uint256 tokensSold;
        address buyer;
    }

    mapping(address => SaleRecord[]) public referallSalesRecords;

    mapping(uint256 => Stage) public stages;
    uint256 public maxStage = 5;
    uint256 currentStageId = 0;

    /**** constructor */
    constructor(
        address _seller,
        address _payment,
        address _token
    ) Ownable(msg.sender) {
        token = IERC20(_token);
        tokenMetadata = IERC20Metadata(_token);
        sellerAddress = _seller;
        paymentAddress = _payment;

        if (block.chainid == 56) {
            UsdtAddress = 0x55d398326f99059fF775485246999027B3197955;
        }  else {
            revert("Unsupported network!");
        }
    }

    function setPartner(address _partner, bool _status) external onlyOwner {
        isPartner[_partner] = _status;
    }

    /***
     * @dev Activate or deactivate the whitelist feature
     */
    function setWhitelistActive(bool _active) external onlyOwner {
        whitelistActive = _active;
    }

    /***
     * @dev Add addresses to the whitelist
     */
    function addToWhitelist(address[] calldata addresses) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            whitelist[addresses[i]] = true;
        }
    }

    /***
     * @dev Remove addresses from the whitelist
     */
    function removeFromWhitelist(address[] calldata addresses)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < addresses.length; i++) {
            whitelist[addresses[i]] = false;
        }
    }

    /***
     * @dev Check if an address is whitelisted
     */
    modifier onlyWhitelisted() {
        require(
            !whitelistActive || whitelist[msg.sender],
            "Address not whitelisted"
        );
        _;
    }

    function calculateReferralReward(uint256 totalPayInUsd, address referral)
        internal
        view
        returns (uint256)
    {
        if (referral == address(0)) return 0;
        uint256 percent = isPartner[referral]
            ? PARTNER_REFERRAL_PERCENT
            : STANDARD_REFERRAL_PERCENT;

        return (totalPayInUsd * percent) / 100;
    }

    function buyInErc20(uint256 _amount, address _referallAddress)
        public
        onlyWhitelisted
    {
        require(presaleActive, "Presale is not active!");
        require(_amount > 0, "Please enter minimum USDT amount!");
        require(_referallAddress != msg.sender, "You cannot refer yourself!");

        uint256 _id = getCurrentStageIdActive();
        require(_id > 0, "Stage info not available!");

        Stage storage currentStage = stages[_id];

        uint256 tokensToReceive = (_amount * 1e18) /
            currentStage.price;

        require(
            currentStage.tokensSold + tokensToReceive <= currentStage.maxTokens,
            "Stage token limit exceeded!"
        );

        require(
            IERC20(UsdtAddress).allowance(msg.sender, address(this)) >=
                _amount,
            "Insufficient USDT allowance!"
        );

        uint256 referralReward = calculateReferralReward(
            _amount,
            _referallAddress
        );

        if (referralReward > 0 && _referallAddress != address(0)) {
            IERC20(UsdtAddress).transferFrom(
                msg.sender,
                _referallAddress,
                referralReward
            );
            _amount -= referralReward;
        }

        IERC20(UsdtAddress).transferFrom(
            msg.sender,
            paymentAddress,
            _amount
        );

        token.transferFrom(sellerAddress, msg.sender, tokensToReceive);

        currentStage.tokensSold += tokensToReceive;
        totalSold += tokensToReceive;

        if (_referallAddress != address(0)) {
            referallSalesRecords[_referallAddress].push(
                SaleRecord({
                    stageId: _id,
                    tokensSold: tokensToReceive,
                    buyer: msg.sender
                })
            );
        }
    }

    /***
     * @dev update token address
     */
    function setToken(address _token) public onlyOwner {
        require(_token != address(0), "Token is zero address!");
        token = IERC20(_token);
        tokenMetadata = IERC20Metadata(_token);
    }

    /***
     * @dev update sellerAddress
     */
    function setSellerAddress(address _seller) public onlyOwner {
        sellerAddress = _seller;
    }

    /***
     * @dev update paementAddress
     */
    function setPaymentAddress(address _payment) public onlyOwner {
        paymentAddress = _payment;
    }

    /***
     * @dev flip presaleActive as true/false
     */
    function flipPresaleActive() public onlyOwner {
        presaleActive = !presaleActive;
    }

    /**
     * @dev Emergency function to withdraw all presale tokens from the contract to the owner's address
     */
    function emergencyWithdraw() public onlyOwner {
        uint256 remainingTokens = token.balanceOf(address(this));
        require(remainingTokens > 0, "No tokens left to withdraw");

        bool success = token.transfer(msg.sender, remainingTokens);
        require(success, "Failed to withdraw tokens");
    }

    /***
     * @dev update maximum stage
     */
    function setMaxStage(uint256 _maxStage) public onlyOwner {
        maxStage = _maxStage;
    }

    /***
     * @dev ading stage info
     */

    function addStage(
        uint256 _price,
        uint256 _maxTokens,
        bool _active
    ) public onlyOwner {
        uint256 _id = currentStageId + 1;
        require(_id <= maxStage, "Maximum stage exceeds!");
        currentStageId += 1;

        stages[_id] = Stage({
            id: _id,
            price: _price,
            maxTokens: _maxTokens,
            tokensSold: 0,
            active: _active
        });
    }

    function setStage(
        uint256 _id,
        uint256 _price,
        uint256 _maxTokens,
        bool _active
    ) public onlyOwner {
        require(stages[_id].id == _id, "ID doesn't exist!");
        stages[_id].price = _price;
        stages[_id].maxTokens = _maxTokens;
        stages[_id].active = _active;
    }

    /***
     * @dev get current stage id active
     */

    function getCurrentStageIdActive() public view returns (uint256) {
        uint256 _id = 0;
        for (uint256 i = 1; i <= currentStageId; i++) {
            if (stages[i].active) {
                _id = i;
                break;
            }
        }
        return _id;
    }

    /***
     * @dev withdrawFunds functions to get remaining funds transfer to seller address
     */
    function withdrawFunds() public onlyOwner {
        require(
            payable(msg.sender).send(address(this).balance),
            "Failed withdraw!"
        );
    }
}
