pragma solidity 0.6.12;

import "./interface/IPancakeRouter02.sol";
import "./lib/Ownable.sol";

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";

contract CMCAirdrop is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    
    enum UserStatus{
        NONE,
        ACTIVE,
        CLAIMED
    }

    IPancakeRouter02 constant public pancakeRouterV2 = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    IBEP20 constant public sbf = IBEP20(0xBb53FcAB7A3616C5be33B9C0AF612f0462b01734);
    IBEP20 constant public busd = IBEP20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);

    mapping(address => UserStatus) public userWhitelistMap;
    uint256 public minimumBUSD;
    uint256 public sbfRewardAmount;

    event ClaimedSBFReward(address indexed userAddr, uint256 amount);

    constructor(uint256 _minimumBUSD, address _owner, uint256 _sbfRewardAmount) public {
        minimumBUSD = _minimumBUSD;
        sbfRewardAmount = _sbfRewardAmount;
        super.initializeOwner(_owner);

        sbf.approve(address(pancakeRouterV2), uint256(-1));
        busd.approve(address(pancakeRouterV2), uint256(-1));
    }
    
    modifier notContract() {
        require(!isContract(msg.sender), "contract is not allowed");
        require(msg.sender == tx.origin, "no proxy contract is allowed");
        _;
    }

    function isContract(address addr) internal view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }

    function addWhitelist(address[] memory _users) onlyOwner() public {
        uint256 len = _users.length;
        for(uint256 i = 0; i < len; i++){
            if(userWhitelistMap[_users[i]] == UserStatus.NONE) {
                userWhitelistMap[_users[i]] = UserStatus.ACTIVE;
            }
        }
    }

    function claimSBFReward(uint256 _sbfAmount, uint256 _busdAmount) notContract public {
        require(userWhitelistMap[msg.sender] == UserStatus.ACTIVE, "invalid user status");
        require(_sbfAmount > 0, "insufficient sbf amount");
        require(_busdAmount >= minimumBUSD, "insufficient busd amount");

        userWhitelistMap[msg.sender] = UserStatus.CLAIMED;

        sbf.safeTransferFrom(address(msg.sender), address(this), _sbfAmount);
        busd.safeTransferFrom(address(msg.sender), address(this), _busdAmount);

        uint256 sbfAmountBefore = sbf.balanceOf(address(this));
        pancakeRouterV2.addLiquidity(address(sbf), address(busd), _sbfAmount, _busdAmount, 0, minimumBUSD, msg.sender, block.timestamp + 3);
        uint256 sbfAmountAfter = sbf.balanceOf(address(this));

        uint sbfAmountReturn = _sbfAmount.sub(sbfAmountBefore.sub(sbfAmountAfter)).add(sbfRewardAmount);

        sbf.safeTransfer(address(msg.sender), sbfAmountReturn);
        busd.safeTransfer(address(msg.sender), busd.balanceOf(address(this)));

        emit ClaimedSBFReward(msg.sender, sbfRewardAmount);
    }

    function setMinimumBUSD(uint256 _minimumBUSD) onlyOwner() public {
        minimumBUSD = _minimumBUSD;
    }

    function setSBFRewardAmount(uint256 _sbfRewardAmount) onlyOwner() public {
        sbfRewardAmount = _sbfRewardAmount;
    }

    function redeemSBF() external onlyOwner {
        uint256 balance = sbf.balanceOf(address(this));
        sbf.safeTransfer(msg.sender, balance);
    }
}