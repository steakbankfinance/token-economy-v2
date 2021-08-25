pragma solidity 0.6.12;

import "./interface/IPancakeRouter02.sol";
import "./lib/Ownable.sol";

import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";

contract CMCAirdrop is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    
    IPancakeRouter02 constant public pancakeRouterV2 = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    IBEP20 constant public sbf = IBEP20(0xBb53FcAB7A3616C5be33B9C0AF612f0462b01734);
    IBEP20 constant public busd = IBEP20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);

    uint256 public sbfRewardAmount;

    enum UserStatus{
        NONE,
        ACTIVE,
        CLAIMED
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

    mapping(address => UserStatus) userWhitelistMap;
    uint256 public minimumBUSD;

    event ClaimedSBFReward(address indexed userAddr, uint256 amount);

    constructor(uint256 _minimumBUSD, address _owner, uint256 _sbfRewardAmount) public {
        minimumBUSD = _minimumBUSD;
        super.initializeOwner(_owner);

        sbfRewardAmount = _sbfRewardAmount;

        sbf.approve(address(pancakeRouterV2), uint256(-1));
        busd.approve(address(pancakeRouterV2), uint256(-1));
    }

    function setMinimumBUSD(uint256 _minimumBUSD) onlyOwner() public {
        minimumBUSD = _minimumBUSD;
    }

    function addWhitelist(address[] memory _users) onlyOwner() public {
        uint256 len = _users.length;
        for(uint256 i = 0; i < len; i++){
            userWhitelistMap[_users[i]] = UserStatus.ACTIVE;
        }
    }

    function claimSBFReward(uint256 _sbfAmount, uint256 _busdAmount) notContract public {
        require(userWhitelistMap[msg.sender] == UserStatus.ACTIVE, "invalid user status");
        require(_busdAmount >= minimumBUSD, "insufficient busd amount");

        userWhitelistMap[msg.sender] = UserStatus.CLAIMED;

        sbf.safeTransferFrom(address(msg.sender), address(this), _sbfAmount);
        busd.safeTransferFrom(address(msg.sender), address(this), _busdAmount);

        uint256 sbfAmountBefore = sbf.balanceOf(address(this));
        pancakeRouterV2.addLiquidity(address(sbf), address(busd), _sbfAmount, _busdAmount, 0, minimumBUSD, msg.sender, block.timestamp + 3);
        uint256 sbfAmountAfter = sbf.balanceOf(address(this));

        uint sbfAmountReturn = sbfAmountBefore.sub(sbfAmountAfter).add(sbfRewardAmount);

        sbf.safeTransferFrom(address(this), address(msg.sender), sbfAmountReturn);
        busd.safeTransferFrom(address(this), address(msg.sender), busd.balanceOf(address(this)));
    }

    function setSBFRewardAmount(uint256 _sbfRewardAmount) onlyOwner() public {
        sbfRewardAmount = _sbfRewardAmount;
    }
}