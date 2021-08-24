pragma solidity 0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";

interface IFarm {
    function initialize(address _owner, IBEP20 _sbf, address taxVault) external;
    function startFarmingPeriod(uint256 farmingPeriod, uint256 startHeight, uint256 sbfRewardPerBlock) external;
    function addPool(uint256 _allocPoint, IBEP20 _lpToken, uint256 maxTaxPercent, uint256 miniTaxFreeDay, bool _withUpdate) external;
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external;

    function deposit(uint256 _pid, uint256 _amount, address _userAddr) external;
    function withdraw(uint256 _pid, uint256 _amount, address _userAddr) external;
    function redeemSBF(address _recipient) external;

    function pendingSBF(uint256 _pid, address _user) external view returns (uint256);
    function lpSupply(uint256 _pid) external view returns (uint256);
}