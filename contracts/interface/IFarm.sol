pragma solidity 0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";

interface IFarm {
    function initialize(address _owner, IBEP20 _sbf) external;
    function startFarmingPeriod(uint256 farmingPeriod, uint256 startHeight, uint256 sbfRewardPerBlock) external;
    function addPool(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate) external;
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external;

    function deposit(uint256 _pid, uint256 _amount, address userAddr) external;
    function withdraw(uint256 _pid, uint256 _amount, address userAddr) external;

    function pendingSBF(uint256 _pid, address _user) external view returns (uint256);
    function getUserAmount(uint256 _pid, address _user) external view returns (uint256);
}