pragma solidity 0.6.12;

import "./interface/IPancakeRouter02.sol";
import "./lib/Ownable.sol";

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";

contract CMCAirdrop is Ownable {
    IPancakeRouter02 constant public pancakeRouterV2 = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    IBEP20 constant public sbf = IBEP20(0xBb53FcAB7A3616C5be33B9C0AF612f0462b01734);
    IBEP20 constant public busd = IBEP20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);

    enum UserStatus{
        NONE,
        ACTIVE,
        CLAIMED
    }

    mapping(address => UserStatus) userWhitelistMap;
    uint256 constant public minimumBUSD;

    event ClaimedSBFReward(address indexed userAddr, uint256 amount);

    constructor(uint256 _minimumBUSD, address _owner) public {
        minimumBUSD = _minimumBUSD;
        super.initializeOwner(_owner);
    }

    function setMinimumBUSD(uint256 _minimumBUSD) onlyOwner() public {

    }

    function addWhitelist(address[] users) onlyOwner() public {

    }

    function claimSBFReward() public {

    }
}