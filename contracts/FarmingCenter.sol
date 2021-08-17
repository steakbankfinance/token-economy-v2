pragma solidity 0.6.12;

import "./lib/SBFRewardVault.sol";
import "./lib/Ownable.sol";

import "./interface/IFarm.sol";

contract FarmingCenter is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    struct UserInfo {
        uint256 amount;
        uint256 timestamp;
    }

    bool public initialized;

    IBEP20 public sbf;

    IFarm public farmingPhase1;
    IFarm public farmingPhase2;
    IFarm public farmingPhase3;
    IFarm public farmingPhase4;

    mapping(uint256 => mapping(address => UserInfo)) public userInfos;
    IBEP20[] public poolInfos;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, uint256 reward);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, uint256 reward);

    constructor() public {}

    function initialize(
        address _owner,
        IBEP20 _sbf,
        IFarm _farmingPhase1,
        IFarm _farmingPhase2,
        IFarm _farmingPhase3,
        IFarm _farmingPhase4,
        address _taxVault
    ) public {
        require(!initialized, "already initialized");
        initialized = true;

        super.initializeOwner(_owner);

        sbf = _sbf;

        farmingPhase1 = _farmingPhase1;
        farmingPhase2 = _farmingPhase2;
        farmingPhase3 = _farmingPhase3;
        farmingPhase4 = _farmingPhase4;

        farmingPhase1.initialize(address(this), _sbf, _taxVault);
        farmingPhase2.initialize(address(this), _sbf, _taxVault);
        farmingPhase3.initialize(address(this), _sbf, _taxVault);
        farmingPhase4.initialize(address(this), _sbf, _taxVault);
    }

    function startFarmingPeriod(uint256 farmingPeriod, uint256 startHeight, uint256 sbfRewardPerBlock) public onlyOwner {
        farmingPhase1.startFarmingPeriod(farmingPeriod, startHeight, sbfRewardPerBlock.mul(10).div(100));
        farmingPhase2.startFarmingPeriod(farmingPeriod, startHeight, sbfRewardPerBlock.mul(30).div(100));
        farmingPhase3.startFarmingPeriod(farmingPeriod, startHeight, sbfRewardPerBlock.mul(30).div(100));
        farmingPhase4.startFarmingPeriod(farmingPeriod, startHeight, sbfRewardPerBlock.mul(30).div(100));
    }

    function addPool(uint256 _allocPoint, IBEP20 _lpToken, uint256 maxTaxPercent, uint256 miniTaxFreeDay, bool _withUpdate) public onlyOwner {
        farmingPhase1.addPool(_allocPoint, _lpToken, maxTaxPercent, miniTaxFreeDay, _withUpdate);
        farmingPhase2.addPool(_allocPoint, _lpToken, maxTaxPercent, miniTaxFreeDay, _withUpdate);
        farmingPhase3.addPool(_allocPoint, _lpToken, maxTaxPercent, miniTaxFreeDay, _withUpdate);
        farmingPhase4.addPool(_allocPoint, _lpToken, maxTaxPercent, miniTaxFreeDay, _withUpdate);
    }

    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        farmingPhase1.set(_pid, _allocPoint, _withUpdate);
        farmingPhase2.set(_pid, _allocPoint, _withUpdate);
        farmingPhase3.set(_pid, _allocPoint, _withUpdate);
        farmingPhase4.set(_pid, _allocPoint, _withUpdate);
    }

    function pendingSBF(uint256 _pid, address _user) external view returns (uint256) {
        return farmingPhase1.pendingSBF(_pid, _user).
        add(farmingPhase2.pendingSBF(_pid, _user)).
        add(farmingPhase3.pendingSBF(_pid, _user)).
        add(farmingPhase4.pendingSBF(_pid, _user));
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        UserInfo storage userInfo = userInfos[_pid][msg.sender];
        userInfo.amount = userInfo.amount.add(_amount);
        poolInfos[_pid].safeTransferFrom(address(msg.sender), address(this), _amount);

        if (userInfo.amount > 0) {
            farmingPhase4.withdraw(_pid, userInfo.amount, msg.sender);
            farmingPhase3.withdraw(_pid, userInfo.amount, msg.sender);
            farmingPhase2.withdraw(_pid, userInfo.amount, msg.sender);
            farmingPhase1.withdraw(_pid, userInfo.amount, msg.sender);
        }
        farmingPhase1.deposit(_pid, _amount, msg.sender);
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        UserInfo storage userInfo = userInfos[_pid][msg.sender];
        require(userInfo.amount >= _amount, "withdraw: not good");
        
        farmingPhase4.withdraw(_pid, userInfo.amount, msg.sender);
        farmingPhase3.withdraw(_pid, userInfo.amount, msg.sender);
        farmingPhase2.withdraw(_pid, userInfo.amount, msg.sender);
        farmingPhase1.withdraw(_pid, _amount, msg.sender);
        
        userInfo.amount = userInfo.amount.sub(_amount);
        poolInfos[_pid].safeTransfer(address(msg.sender), _amount);
    }

    function migrateAgeFarming() public {

    }

    function batchMigrateAgeFarming(address[] memory users) public {

    }
}
