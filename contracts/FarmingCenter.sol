pragma solidity 0.6.12;

import "./lib/SBFRewardVault.sol";
import "./lib/Ownable.sol";

import "./interface/IFarm.sol";
import "./interface/IMintBurnToken.sol";

contract FarmingCenter is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    struct UserInfo {
        uint256 amount;
        uint256 timestamp;
    }
    
    uint256 constant public SBF_POOL_ID = 0;
    uint256 constant public LP_LBNB_BNB_POOL_ID = 1;
    uint256 constant public LP_SBF_BUSD_POOL_ID = 2;

    bool public initialized;
    bool public pool_initialized;

    address public aSBF;

    IBEP20 public sbf;
    IBEP20 public lpLBNB2BNB;
    IBEP20 public lpSBF2BUSD;

    IFarm public farmingPhase1;
    IFarm public farmingPhase2;
    IFarm public farmingPhase3;
    IFarm public farmingPhase4;

    uint256 public startBlock;
    uint256 public endBlock;

    mapping(uint256 => mapping(address => UserInfo)) public userInfos;

    event Deposit(address indexed userInfo, uint256 indexed pid, uint256 amount, uint256 reward);
    event Withdraw(address indexed userInfo, uint256 indexed pid, uint256 amount, uint256 reward);
    event EmergencyWithdraw(address indexed userInfo, uint256 indexed pid, uint256 amount);

    constructor() public {}

    function initialize(
        address _owner,
        address _aSBF,
        IBEP20 _sbf,
        IBEP20 _lpLBNB2BNB,
        IBEP20 _lpSBF2BUSD,

        IFarm _farmingPhase1,
        IFarm _farmingPhase2,
        IFarm _farmingPhase3,
        IFarm _farmingPhase4,
        address _taxVault
    ) public {
        require(!initialized, "already initialized");
        initialized = true;

        super.initializeOwner(_owner);

        aSBF = _aSBF;

        sbf = _sbf;
        lpLBNB2BNB = _lpLBNB2BNB;
        lpSBF2BUSD = _lpSBF2BUSD;

        farmingPhase1 = _farmingPhase1;
        farmingPhase2 = _farmingPhase2;
        farmingPhase3 = _farmingPhase3;
        farmingPhase4 = _farmingPhase4;

        farmingPhase1.initialize(address(this), _sbf, _taxVault);
        farmingPhase2.initialize(address(this), _sbf, _taxVault);
        farmingPhase3.initialize(address(this), _sbf, _taxVault);
        farmingPhase4.initialize(address(this), _sbf, _taxVault);
    }

    function initPools(uint256[] calldata _allocPoints, uint256[] calldata _maxTaxPercents, uint256[] calldata _miniTaxFreeDays, bool _withUpdate) external onlyOwner {
        require(initialized, "farm is not initialized");
        require(!pool_initialized, "pool already initialized");
        pool_initialized = true;

        require(_allocPoints.length==3&&_maxTaxPercents.length==3&&_miniTaxFreeDays.length==3, "wrong array length");

        farmingPhase1.addPool(_allocPoints[0], sbf, _maxTaxPercents[0], _miniTaxFreeDays[0], _withUpdate);
        farmingPhase2.addPool(_allocPoints[0], sbf, _maxTaxPercents[0], _miniTaxFreeDays[0], _withUpdate);
        farmingPhase3.addPool(_allocPoints[0], sbf, _maxTaxPercents[0], _miniTaxFreeDays[0], _withUpdate);
        farmingPhase4.addPool(_allocPoints[0], sbf, _maxTaxPercents[0], _miniTaxFreeDays[0], _withUpdate);

        farmingPhase1.addPool(_allocPoints[1], lpLBNB2BNB, _maxTaxPercents[1], _miniTaxFreeDays[1], _withUpdate);
        farmingPhase2.addPool(_allocPoints[1], lpLBNB2BNB, _maxTaxPercents[1], _miniTaxFreeDays[1], _withUpdate);
        farmingPhase3.addPool(_allocPoints[1], lpLBNB2BNB, _maxTaxPercents[1], _miniTaxFreeDays[1], _withUpdate);
        farmingPhase4.addPool(_allocPoints[1], lpLBNB2BNB, _maxTaxPercents[1], _miniTaxFreeDays[1], _withUpdate);

        farmingPhase1.addPool(_allocPoints[2], lpSBF2BUSD, _maxTaxPercents[2], _miniTaxFreeDays[2], _withUpdate);
        farmingPhase2.addPool(_allocPoints[2], lpSBF2BUSD, _maxTaxPercents[2], _miniTaxFreeDays[2], _withUpdate);
        farmingPhase3.addPool(_allocPoints[2], lpSBF2BUSD, _maxTaxPercents[2], _miniTaxFreeDays[2], _withUpdate);
        farmingPhase4.addPool(_allocPoints[2], lpSBF2BUSD, _maxTaxPercents[2], _miniTaxFreeDays[2], _withUpdate);
    }

    function startFarmingPeriod(uint256 farmingPeriod, uint256 startHeight, uint256 sbfRewardPerBlock) public onlyOwner {
        require(pool_initialized, "pool is not initialized");

        startBlock = startHeight;
        endBlock = startHeight.add(farmingPeriod);

        uint256 totalSBFAmount = farmingPeriod.mul(sbfRewardPerBlock);
        sbf.safeTransferFrom(msg.sender, address(this), totalSBFAmount);

        sbf.approve(address(farmingPhase1), totalSBFAmount.mul(10).div(100));
        sbf.approve(address(farmingPhase2), totalSBFAmount.mul(30).div(100));
        sbf.approve(address(farmingPhase3), totalSBFAmount.mul(30).div(100));
        sbf.approve(address(farmingPhase4), totalSBFAmount.mul(30).div(100));

        farmingPhase1.startFarmingPeriod(farmingPeriod, startHeight, sbfRewardPerBlock.mul(10).div(100));
        farmingPhase2.startFarmingPeriod(farmingPeriod, startHeight, sbfRewardPerBlock.mul(30).div(100));
        farmingPhase3.startFarmingPeriod(farmingPeriod, startHeight, sbfRewardPerBlock.mul(30).div(100));
        farmingPhase4.startFarmingPeriod(farmingPeriod, startHeight, sbfRewardPerBlock.mul(30).div(100));
    }

    /*
     pid 0 -> sbf pool
     pid 1 -> lbnb2bnb pool
     pid 2 -> sbf2busd pool
    */
    function set(uint256 _pid, uint256 _allocPoints, bool _withUpdate) public onlyOwner {
        farmingPhase1.set(_pid, _allocPoints, _withUpdate);
        farmingPhase2.set(_pid, _allocPoints, _withUpdate);
        farmingPhase3.set(_pid, _allocPoints, _withUpdate);
        farmingPhase4.set(_pid, _allocPoints, _withUpdate);
    }

    function redeemSBF(address recipient) public onlyOwner {
        require(block.number>=endBlock, "farming is not end");
        farmingPhase1.redeemSBF(recipient);
        farmingPhase2.redeemSBF(recipient);
        farmingPhase3.redeemSBF(recipient);
        farmingPhase4.redeemSBF(recipient);
    }

    function pendingSBF(uint256 _pid, address _user) external view returns (uint256) {
        return farmingPhase1.pendingSBF(_pid, _user).
        add(farmingPhase2.pendingSBF(_pid, _user)).
        add(farmingPhase3.pendingSBF(_pid, _user)).
        add(farmingPhase4.pendingSBF(_pid, _user));
    }

    function depositSBFPool(uint256 _amount) public {
        UserInfo storage userInfo = userInfos[SBF_POOL_ID][msg.sender];
        if (farmingPhase4.getUserAmount(SBF_POOL_ID, msg.sender) > 0) {
            farmingPhase4.withdraw(SBF_POOL_ID, userInfo.amount, msg.sender);
        }
        if (farmingPhase3.getUserAmount(SBF_POOL_ID, msg.sender) > 0) {
            farmingPhase3.withdraw(SBF_POOL_ID, userInfo.amount, msg.sender);
        }
        if (farmingPhase2.getUserAmount(SBF_POOL_ID, msg.sender) > 0) {
            farmingPhase2.withdraw(SBF_POOL_ID, userInfo.amount, msg.sender);
        }
        if (farmingPhase1.getUserAmount(SBF_POOL_ID, msg.sender) > 0) {
            farmingPhase1.withdraw(SBF_POOL_ID, 0, msg.sender);
        }

        sbf.safeTransferFrom(address(msg.sender), address(this), _amount);
        userInfo.amount = userInfo.amount.add(_amount);
        userInfo.timestamp = block.timestamp;
        farmingPhase1.deposit(SBF_POOL_ID, _amount, msg.sender);
        IMintBurnToken(aSBF).mintTo(msg.sender, _amount);
    }

    function withdrawSBFPool(uint256 _amount) public {
        IBEP20(aSBF).transferFrom(msg.sender, address(this), _amount);
        IMintBurnToken(aSBF).burn(_amount);

        UserInfo storage userInfo = userInfos[SBF_POOL_ID][msg.sender];
        require(userInfo.amount >= _amount, "withdraw: not good");

        if (farmingPhase4.getUserAmount(SBF_POOL_ID, msg.sender) > 0) {
            farmingPhase4.withdraw(SBF_POOL_ID, userInfo.amount, msg.sender);
        }
        if (farmingPhase3.getUserAmount(SBF_POOL_ID, msg.sender) > 0) {
            farmingPhase3.withdraw(SBF_POOL_ID, userInfo.amount, msg.sender);
        }
        if (farmingPhase2.getUserAmount(SBF_POOL_ID, msg.sender) > 0) {
            farmingPhase2.withdraw(SBF_POOL_ID, userInfo.amount, msg.sender);
        }
        if (farmingPhase1.getUserAmount(SBF_POOL_ID, msg.sender) > 0) {
            farmingPhase1.withdraw(SBF_POOL_ID, _amount, msg.sender);
        }
        
        userInfo.amount = userInfo.amount.sub(_amount);
        userInfo.timestamp = block.timestamp;
        sbf.safeTransfer(address(msg.sender), _amount);
    }

    function depositLBNB2BNBPool(uint256 _amount) public {
        UserInfo storage userInfo = userInfos[LP_LBNB_BNB_POOL_ID][msg.sender];

        farmingPhase4.deposit(LP_LBNB_BNB_POOL_ID, _amount, msg.sender);
        farmingPhase3.deposit(LP_LBNB_BNB_POOL_ID, _amount, msg.sender);
        farmingPhase2.deposit(LP_LBNB_BNB_POOL_ID, _amount, msg.sender);
        farmingPhase1.deposit(LP_LBNB_BNB_POOL_ID, _amount, msg.sender);

        lpLBNB2BNB.safeTransferFrom(address(msg.sender), address(this), _amount);
        userInfo.amount = userInfo.amount.add(_amount);
        userInfo.timestamp = block.timestamp;
    }

    function withdrawLBNB2BNBPool(uint256 _amount) public {
        UserInfo storage userInfo = userInfos[LP_LBNB_BNB_POOL_ID][msg.sender];
        require(userInfo.amount >= _amount, "withdraw: not good");

        farmingPhase4.withdraw(LP_LBNB_BNB_POOL_ID, _amount, msg.sender);
        farmingPhase3.withdraw(LP_LBNB_BNB_POOL_ID, _amount, msg.sender);
        farmingPhase2.withdraw(LP_LBNB_BNB_POOL_ID, _amount, msg.sender);
        farmingPhase1.withdraw(LP_LBNB_BNB_POOL_ID, _amount, msg.sender);

        userInfo.amount = userInfo.amount.sub(_amount);
        userInfo.timestamp = block.timestamp;
        lpLBNB2BNB.safeTransfer(address(msg.sender), _amount);
    }

    function depositSBF2BUSDPool(uint256 _amount) public {
        UserInfo storage userInfo = userInfos[LP_SBF_BUSD_POOL_ID][msg.sender];

        farmingPhase3.deposit(LP_SBF_BUSD_POOL_ID, _amount, msg.sender);
        farmingPhase2.deposit(LP_SBF_BUSD_POOL_ID, _amount, msg.sender);
        farmingPhase1.deposit(LP_SBF_BUSD_POOL_ID, _amount, msg.sender);

        userInfo.amount = userInfo.amount.add(_amount);
        userInfo.timestamp = block.timestamp;
        lpSBF2BUSD.safeTransferFrom(address(msg.sender), address(this), _amount);
    }

    function withdrawSBF2BUSDPool(uint256 _amount) public {
        UserInfo storage userInfo = userInfos[LP_SBF_BUSD_POOL_ID][msg.sender];
        require(userInfo.amount >= _amount, "withdraw: not good");

        farmingPhase3.withdraw(LP_SBF_BUSD_POOL_ID, _amount, msg.sender);
        farmingPhase2.withdraw(LP_SBF_BUSD_POOL_ID, _amount, msg.sender);
        farmingPhase1.withdraw(LP_SBF_BUSD_POOL_ID, _amount, msg.sender);

        userInfo.amount = userInfo.amount.sub(_amount);
        userInfo.timestamp = block.timestamp;
        lpSBF2BUSD.safeTransfer(address(msg.sender), _amount);
    }

    function emergencyWithdrawSBF() public {
        UserInfo storage userInfo = userInfos[SBF_POOL_ID][msg.sender];
        sbf.safeTransfer(address(msg.sender), userInfo.amount);
        emit EmergencyWithdraw(msg.sender, SBF_POOL_ID, userInfo.amount);
        userInfo.amount = 0;
    }

    function emergencyWithdrawLBNB2BNBLP() public {
        UserInfo storage userInfo = userInfos[LP_LBNB_BNB_POOL_ID][msg.sender];
        lpLBNB2BNB.safeTransfer(address(msg.sender), userInfo.amount);
        emit EmergencyWithdraw(msg.sender, LP_LBNB_BNB_POOL_ID, userInfo.amount);
        userInfo.amount = 0;
    }

    function emergencyWithdrawSBF2BUSDLP() public {
        UserInfo storage userInfo = userInfos[LP_SBF_BUSD_POOL_ID][msg.sender];
        lpSBF2BUSD.safeTransfer(address(msg.sender), userInfo.amount);
        emit EmergencyWithdraw(msg.sender, LP_SBF_BUSD_POOL_ID, userInfo.amount);
        userInfo.amount = 0;
    }

    function migrateSBFPoolAgeFarming(address user) public {
        bool needMigration = false;
        UserInfo storage userInfo = userInfos[SBF_POOL_ID][user];
        if (block.timestamp-userInfo.timestamp>7*86400 && farmingPhase2.getUserAmount(SBF_POOL_ID, user)==0) {
            farmingPhase2.deposit(SBF_POOL_ID, userInfo.amount, user);
            needMigration = true;
        }
        if (block.timestamp-userInfo.timestamp>30*86400 && farmingPhase3.getUserAmount(SBF_POOL_ID, user)==0) {
            farmingPhase3.deposit(SBF_POOL_ID, userInfo.amount, user);
            needMigration = true;
        }
        if (block.timestamp-userInfo.timestamp>60*86400 && farmingPhase4.getUserAmount(SBF_POOL_ID, user)==0) {
            farmingPhase4.deposit(SBF_POOL_ID, userInfo.amount, user);
            needMigration = true;
        }
        require(needMigration, "no need to migration");
    }

    function batchMigrateSBFPoolAgeFarming(address[] memory users) public {
        for(uint256 idx=0;idx<users.length;idx++){
            migrateSBFPoolAgeFarming(users[idx]);
        }
    }
}
