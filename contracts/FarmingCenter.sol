pragma solidity 0.6.12;

import "./lib/Ownable.sol";
import "./interface/IFarm.sol";
import "./interface/IMintBurnToken.sol";

import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";

contract FarmingCenter is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    struct FarmingInfo {
        address userAddr;
        uint256 poolID;
        uint256 amount;
        uint256 timestamp;
        uint256 farmingPhaseAmount;
    }
    
    uint256 constant public POOL_ID_SBF = 0;
    uint256 constant public POOL_ID_LP_LBNB_BNB = 1;
    uint256 constant public POOL_ID_LP_SBF_BUSD = 2;

    uint256 constant public THREE_MONTHS = 7776000; // 90 * 86400
    //TODO change to 86400 for mainnet
    uint256 constant public ONE_DAY = 1; // 86400

    bool public initialized;
    bool public pool_initialized;

    address public aSBF;
    address public aLBNB2BNBLP;
    address public aSBF2BUSDLP;

    uint256 public farmingIdx;
    mapping(uint256 => FarmingInfo) public farmingInfoMap;
    mapping(address => uint256[]) public userToFarmingIDsMap;
    mapping(uint256 => uint256) public poolAllocPoints;

    IBEP20 public sbf;
    IBEP20 public lpLBNB2BNB;
    IBEP20 public lpSBF2BUSD;

    IFarm public farmingPhase1;
    IFarm public farmingPhase2;
    IFarm public farmingPhase3;
    IFarm public farmingPhase4;

    uint256 public startBlock;
    uint256 public endBlock;
    uint256 public sbfRewardPerBlock;

    event Deposit(address indexed userInfo, uint256 indexed pid, uint256 amount, uint256 reward);
    event Withdraw(address indexed userInfo, uint256 indexed pid, uint256 amount, uint256 reward);
    event WithdrawTax(address indexed lpAddr, address indexed userAddr, uint256 amount);
    event EmergencyWithdraw(address indexed userInfo, uint256 indexed pid, uint256 amount);

    constructor() public {}

    function initialize(
        address _owner,
        address _aSBF,
        address _aLBNB2BNBLP,
        address _aSBF2BUSDLP,

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
        aLBNB2BNBLP = _aLBNB2BNBLP;
        aSBF2BUSDLP = _aSBF2BUSDLP;

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

        poolAllocPoints[POOL_ID_SBF] = _allocPoints[0];
        farmingPhase1.addPool(_allocPoints[0], sbf, _maxTaxPercents[0], _miniTaxFreeDays[0], _withUpdate);
        farmingPhase2.addPool(_allocPoints[0], sbf, _maxTaxPercents[0], _miniTaxFreeDays[0], _withUpdate);
        farmingPhase3.addPool(_allocPoints[0], sbf, _maxTaxPercents[0], _miniTaxFreeDays[0], _withUpdate);
        farmingPhase4.addPool(_allocPoints[0], sbf, _maxTaxPercents[0], _miniTaxFreeDays[0], _withUpdate);

        poolAllocPoints[POOL_ID_LP_LBNB_BNB] = _allocPoints[1];
        farmingPhase1.addPool(_allocPoints[1], lpLBNB2BNB, _maxTaxPercents[1], _miniTaxFreeDays[1], _withUpdate);
        farmingPhase2.addPool(_allocPoints[1], lpLBNB2BNB, _maxTaxPercents[1], _miniTaxFreeDays[1], _withUpdate);
        farmingPhase3.addPool(_allocPoints[1], lpLBNB2BNB, _maxTaxPercents[1], _miniTaxFreeDays[1], _withUpdate);
        farmingPhase4.addPool(_allocPoints[1], lpLBNB2BNB, _maxTaxPercents[1], _miniTaxFreeDays[1], _withUpdate);

        poolAllocPoints[POOL_ID_LP_SBF_BUSD] = _allocPoints[2];
        farmingPhase1.addPool(_allocPoints[2], lpSBF2BUSD, _maxTaxPercents[2], _miniTaxFreeDays[2], _withUpdate);
        farmingPhase2.addPool(_allocPoints[2], lpSBF2BUSD, _maxTaxPercents[2], _miniTaxFreeDays[2], _withUpdate);
        farmingPhase3.addPool(_allocPoints[2], lpSBF2BUSD, _maxTaxPercents[2], _miniTaxFreeDays[2], _withUpdate);
        farmingPhase4.addPool(_allocPoints[2], lpSBF2BUSD, _maxTaxPercents[2], _miniTaxFreeDays[2], _withUpdate);
    }

    function startFarmingPeriod(uint256 _farmingPeriod, uint256 _startHeight, uint256 _sbfRewardPerBlock) public onlyOwner {
        require(pool_initialized, "pool is not initialized");

        startBlock = _startHeight;
        endBlock = _startHeight.add(_farmingPeriod);

        uint256 totalSBFAmount = _farmingPeriod.mul(_sbfRewardPerBlock);
        sbf.safeTransferFrom(msg.sender, address(this), totalSBFAmount);

        sbf.approve(address(farmingPhase1), totalSBFAmount.mul(10).div(100));
        sbf.approve(address(farmingPhase2), totalSBFAmount.mul(30).div(100));
        sbf.approve(address(farmingPhase3), totalSBFAmount.mul(30).div(100));
        sbf.approve(address(farmingPhase4), totalSBFAmount.mul(30).div(100));

        farmingPhase1.startFarmingPeriod(_farmingPeriod, _startHeight, _sbfRewardPerBlock.mul(10).div(100));
        farmingPhase2.startFarmingPeriod(_farmingPeriod, _startHeight, _sbfRewardPerBlock.mul(30).div(100));
        farmingPhase3.startFarmingPeriod(_farmingPeriod, _startHeight, _sbfRewardPerBlock.mul(30).div(100));
        farmingPhase4.startFarmingPeriod(_farmingPeriod, _startHeight, _sbfRewardPerBlock.mul(30).div(100));

        sbfRewardPerBlock = _sbfRewardPerBlock;
    }

    /*
     pid 0 -> sbf pool
     pid 1 -> lbnb2bnb pool
     pid 2 -> sbf2busd pool
    */
    function set(uint256 _pid, uint256 _allocPoints, bool _withUpdate) public onlyOwner {
        poolAllocPoints[_pid] = _allocPoints;

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

    function farmingSpeed(uint256 _pid, address _user) external view returns (uint256) {
        uint256[] memory farmingIdxs = userToFarmingIDsMap[_user];
        uint256 farmingIdxsLength = farmingIdxs.length;

        uint256[] memory phaseAmountArray = new uint256[](4);
        for (uint256 idx=0;idx<farmingIdxsLength;idx++){
            FarmingInfo memory farmingInfo = farmingInfoMap[farmingIdxs[idx]];
            if (farmingInfo.poolID != _pid) {
                continue;
            }
            phaseAmountArray[farmingInfo.farmingPhaseAmount-1] = phaseAmountArray[farmingInfo.farmingPhaseAmount-1].add(farmingInfo.amount);
        }
        uint256 totalAllocPoints = poolAllocPoints[0].add(poolAllocPoints[1]).add(poolAllocPoints[2]);
        uint256 poolSBFRewardPerBlock = sbfRewardPerBlock.mul(poolAllocPoints[_pid]).div(totalAllocPoints);

        uint256 totalPhaseAmount;
        uint256 accumulatePhaseAmount = phaseAmountArray[3];
        if (farmingPhase4.lpSupply(_pid)!=0) {
            totalPhaseAmount = totalPhaseAmount.add(accumulatePhaseAmount.mul(30).mul(poolSBFRewardPerBlock).div(farmingPhase4.lpSupply(_pid)));
        }

        accumulatePhaseAmount = accumulatePhaseAmount.add(phaseAmountArray[2]);
        if (farmingPhase3.lpSupply(_pid)!=0) {
            totalPhaseAmount = totalPhaseAmount.add(accumulatePhaseAmount.mul(30).mul(poolSBFRewardPerBlock).div(farmingPhase3.lpSupply(_pid)));
        }

        accumulatePhaseAmount = accumulatePhaseAmount.add(phaseAmountArray[1]);
        if (farmingPhase2.lpSupply(_pid)!=0) {
            totalPhaseAmount = totalPhaseAmount.add(accumulatePhaseAmount.mul(30).mul(poolSBFRewardPerBlock).div(farmingPhase2.lpSupply(_pid)));
        }

        accumulatePhaseAmount = accumulatePhaseAmount.add(phaseAmountArray[0]);
        if (farmingPhase1.lpSupply(_pid)!=0) {
            totalPhaseAmount = totalPhaseAmount.add(accumulatePhaseAmount.mul(10).mul(poolSBFRewardPerBlock).div(farmingPhase1.lpSupply(_pid)));
        }

        return totalPhaseAmount.div(100);
    }

    function depositSBFPool(uint256 _amount) public {
        if (_amount>0){
            farmingInfoMap[farmingIdx] = FarmingInfo({
                userAddr: msg.sender,
                poolID: POOL_ID_SBF,
                amount: _amount,
                timestamp: block.timestamp,
                farmingPhaseAmount: 1
            });
            userToFarmingIDsMap[msg.sender].push(farmingIdx);
            farmingIdx++;
        }

        sbf.safeTransferFrom(address(msg.sender), address(this), _amount);

        farmingPhase1.deposit(POOL_ID_SBF, _amount, msg.sender);
        IMintBurnToken(aSBF).mintTo(msg.sender, _amount);
    }

    function withdrawSBFPool(uint256 _amount, uint256 _farmingIdx) public {
        FarmingInfo storage farmingInfo = farmingInfoMap[_farmingIdx];
        require(farmingInfo.userAddr==msg.sender, "can't withdraw other farming");
        require(farmingInfo.amount>=_amount, "withdraw amount too much");

        IBEP20(aSBF).transferFrom(msg.sender, address(this), _amount);
        IMintBurnToken(aSBF).burn(_amount);

        if (farmingInfo.farmingPhaseAmount >= 4) {
            farmingPhase4.withdraw(POOL_ID_SBF, farmingInfo.amount, farmingInfo.userAddr);
        }
        if (farmingInfo.farmingPhaseAmount >= 3) {
            farmingPhase3.withdraw(POOL_ID_SBF, farmingInfo.amount, farmingInfo.userAddr);
        }
        if (farmingInfo.farmingPhaseAmount >= 2) {
            farmingPhase2.withdraw(POOL_ID_SBF, farmingInfo.amount, farmingInfo.userAddr);
        }
        farmingPhase1.withdraw(POOL_ID_SBF, _amount, farmingInfo.userAddr);

        if (farmingInfo.amount == _amount) {
            uint256[] storage farmingIdxs = userToFarmingIDsMap[msg.sender];
            uint256 farmingIdxsLength = farmingIdxs.length;
            for (uint256 idx=0;idx<farmingIdxsLength;idx++){
                if (farmingIdxs[idx]==_farmingIdx) {
                    farmingIdxs[idx]=farmingIdxs[farmingIdxsLength-1];
                    break;
                }
            }
            farmingIdxs.pop();
            delete farmingInfoMap[_farmingIdx];
        } else {
            farmingInfo.amount = farmingInfo.amount.sub(_amount);
            farmingInfo.timestamp = block.timestamp;
        }
        sbf.safeTransfer(address(msg.sender), _amount);
    }

    function batchWithdrawSBFPool(uint256[] memory _farmingIdxs) public {
        for(uint256 idx=0;idx<_farmingIdxs.length;idx++){
            FarmingInfo memory farmingInfo = farmingInfoMap[_farmingIdxs[idx]];
            withdrawSBFPool(farmingInfo.amount, _farmingIdxs[idx]);
        }
    }

    function depositLBNB2BNBPool(uint256 _amount) public {
        if (_amount>0){
            farmingInfoMap[farmingIdx] = FarmingInfo({
                userAddr: msg.sender,
                poolID: POOL_ID_LP_LBNB_BNB,
                amount: _amount,
                timestamp: block.timestamp,
                farmingPhaseAmount: 4
            });
            userToFarmingIDsMap[msg.sender].push(farmingIdx);
            farmingIdx++;

            lpLBNB2BNB.safeTransferFrom(address(msg.sender), address(this), _amount);
        }

        farmingPhase1.deposit(POOL_ID_LP_LBNB_BNB, _amount, msg.sender);
        farmingPhase2.deposit(POOL_ID_LP_LBNB_BNB, _amount, msg.sender);
        farmingPhase3.deposit(POOL_ID_LP_LBNB_BNB, _amount, msg.sender);
        farmingPhase4.deposit(POOL_ID_LP_LBNB_BNB, _amount, msg.sender);
        
        IMintBurnToken(aLBNB2BNBLP).mintTo(msg.sender, _amount);
    }

    function withdrawLBNB2BNBPool(uint256 _amount, uint256 _farmingIdx) public {
        FarmingInfo storage farmingInfo = farmingInfoMap[_farmingIdx];
        require(farmingInfo.userAddr==msg.sender, "can't withdraw other farming");
        require(_amount>0, "withdraw amount must be positive");
        require(farmingInfo.amount>=_amount, "withdraw amount too much");
        
        IBEP20(aLBNB2BNBLP).transferFrom(msg.sender, address(this), _amount);
        IMintBurnToken(aLBNB2BNBLP).burn(_amount);

        farmingPhase4.withdraw(POOL_ID_LP_LBNB_BNB, _amount, msg.sender);
        farmingPhase3.withdraw(POOL_ID_LP_LBNB_BNB, _amount, msg.sender);
        farmingPhase2.withdraw(POOL_ID_LP_LBNB_BNB, _amount, msg.sender);
        farmingPhase1.withdraw(POOL_ID_LP_LBNB_BNB, _amount, msg.sender);

        lpLBNB2BNB.safeTransfer(msg.sender, _amount);

        if (farmingInfo.amount == _amount) {
            uint256[] storage farmingIdxs = userToFarmingIDsMap[msg.sender];
            uint256 farmingIdxsLength = farmingIdxs.length;
            for (uint256 idx=0;idx<farmingIdxsLength;idx++){
                if (farmingIdxs[idx]==_farmingIdx) {
                    farmingIdxs[idx]=farmingIdxs[farmingIdxsLength-1];
                    break;
                }
            }
            farmingIdxs.pop();
            delete farmingInfoMap[_farmingIdx];
        } else {
            farmingInfo.amount = farmingInfo.amount.sub(_amount);
            farmingInfo.timestamp = block.timestamp;
        }
    }

    function batchWithdrawLBNB2BNBPool(uint256[] memory _farmingIdxs) public {
        for(uint256 idx=0;idx<_farmingIdxs.length;idx++){
            FarmingInfo memory farmingInfo = farmingInfoMap[_farmingIdxs[idx]];
            withdrawLBNB2BNBPool(farmingInfo.amount, _farmingIdxs[idx]);
        }
    }

    function depositSBF2BUSDPool(uint256 _amount) public {
        if (_amount>0){
            farmingInfoMap[farmingIdx] = FarmingInfo({
                userAddr: msg.sender,
                poolID: POOL_ID_LP_SBF_BUSD,
                amount: _amount,
                timestamp: block.timestamp,
                farmingPhaseAmount: 3
            });
            userToFarmingIDsMap[msg.sender].push(farmingIdx);
            farmingIdx++;
        }

        lpSBF2BUSD.safeTransferFrom(address(msg.sender), address(this), _amount);

        farmingPhase1.deposit(POOL_ID_LP_SBF_BUSD, _amount, msg.sender);
        farmingPhase2.deposit(POOL_ID_LP_SBF_BUSD, _amount, msg.sender);
        farmingPhase3.deposit(POOL_ID_LP_SBF_BUSD, _amount, msg.sender);

        IMintBurnToken(aSBF2BUSDLP).mintTo(msg.sender, _amount);
    }

    function withdrawSBF2BUSDPool(uint256 _amount, uint256 _farmingIdx) public {
        FarmingInfo storage farmingInfo = farmingInfoMap[_farmingIdx];
        require(farmingInfo.userAddr==msg.sender, "can't withdraw other farming");
        require(_amount>0, "withdraw amount must be positive");
        require(farmingInfo.amount>=_amount, "withdraw amount too much");

        IBEP20(aSBF2BUSDLP).transferFrom(msg.sender, address(this), _amount);
        IMintBurnToken(aSBF2BUSDLP).burn(_amount);

        farmingPhase3.withdraw(POOL_ID_LP_SBF_BUSD, _amount, msg.sender);
        farmingPhase2.withdraw(POOL_ID_LP_SBF_BUSD, _amount, msg.sender);
        farmingPhase1.withdraw(POOL_ID_LP_SBF_BUSD, _amount, msg.sender);

        lpSBF2BUSD.safeTransfer(msg.sender, _amount);

        if (farmingInfo.amount == _amount) {
            uint256[] storage farmingIdxs = userToFarmingIDsMap[msg.sender];
            uint256 farmingIdxsLength = farmingIdxs.length;
            for (uint256 idx=0;idx<farmingIdxsLength;idx++){
                if (farmingIdxs[idx]==_farmingIdx) {
                    farmingIdxs[idx]=farmingIdxs[farmingIdxsLength-1];
                    break;
                }
            }
            farmingIdxs.pop();
            delete farmingInfoMap[_farmingIdx];
        } else {
            farmingInfo.amount = farmingInfo.amount.sub(_amount);
            farmingInfo.timestamp = block.timestamp;
        }
    }

    function batchWithdrawSBF2BUSDPool(uint256[] memory _farmingIdxs) public {
        for(uint256 idx=0;idx<_farmingIdxs.length;idx++){
            FarmingInfo memory farmingInfo = farmingInfoMap[_farmingIdxs[idx]];
            withdrawSBF2BUSDPool(farmingInfo.amount, _farmingIdxs[idx]);
        }
    }

    function emergencyWithdrawSBF(uint256[] memory _farmingIdxs) public {
        for(uint256 idx=0;idx<_farmingIdxs.length;idx++){
            FarmingInfo memory farmingInfo = farmingInfoMap[_farmingIdxs[idx]];
            require(farmingInfo.userAddr==msg.sender, "can't withdraw other farming");
            sbf.safeTransfer(address(msg.sender), farmingInfo.amount);
            emit EmergencyWithdraw(msg.sender, POOL_ID_SBF, farmingInfo.amount);
            delete farmingInfoMap[_farmingIdxs[idx]];
            deleteUserFarmingIDs(_farmingIdxs[idx]);
        }
    }

    function emergencyWithdrawLBNB2BNBLP(uint256[] memory _farmingIdxs) public {
        for(uint256 idx=0;idx<_farmingIdxs.length;idx++){
            FarmingInfo memory farmingInfo = farmingInfoMap[_farmingIdxs[idx]];
            require(farmingInfo.userAddr==msg.sender, "can't withdraw other farming");
            lpLBNB2BNB.safeTransfer(address(msg.sender), farmingInfo.amount);
            emit EmergencyWithdraw(msg.sender, POOL_ID_LP_LBNB_BNB, farmingInfo.amount);
            delete farmingInfoMap[_farmingIdxs[idx]];
            deleteUserFarmingIDs(_farmingIdxs[idx]);
        }
    }

    function emergencyWithdrawSBF2BUSDLP(uint256[] memory _farmingIdxs) public {
        for(uint256 idx=0;idx<_farmingIdxs.length;idx++){
            FarmingInfo memory farmingInfo = farmingInfoMap[_farmingIdxs[idx]];
            require(farmingInfo.userAddr==msg.sender, "can't withdraw other farming");
            lpSBF2BUSD.safeTransfer(address(msg.sender), farmingInfo.amount);
            emit EmergencyWithdraw(msg.sender, POOL_ID_SBF, farmingInfo.amount);
            delete farmingInfoMap[_farmingIdxs[idx]];
            deleteUserFarmingIDs(_farmingIdxs[idx]);
        }
    }

    function deleteUserFarmingIDs(uint256 _idxs) internal {
        uint256[] storage farmingIdxs = userToFarmingIDsMap[msg.sender];
        uint256 farmingIdxsLength = farmingIdxs.length;
        for (uint256 idx=0;idx<farmingIdxsLength;idx++){
            if (farmingIdxs[idx]==_idxs) {
                farmingIdxs[idx]=farmingIdxs[farmingIdxsLength-1];
                break;
            }
        }
        farmingIdxs.pop();
        
        if(farmingIdxs.length==0) {
            delete farmingIdxs;
        }
    }

    function migrateSBFPoolAgeFarming(uint256 _farmingIdx) public {
        bool needMigration = false;
        FarmingInfo storage farmingInfo = farmingInfoMap[_farmingIdx];
        require(farmingInfo.userAddr!=address(0x0), "empty farming info");
        if (block.timestamp-farmingInfo.timestamp>7*ONE_DAY&&farmingInfo.farmingPhaseAmount<2) {
            farmingPhase2.deposit(POOL_ID_SBF, farmingInfo.amount, farmingInfo.userAddr);
            farmingInfo.farmingPhaseAmount = 2;
            needMigration = true;
        }
        if (block.timestamp-farmingInfo.timestamp>30*ONE_DAY&&farmingInfo.farmingPhaseAmount<3) {
            farmingPhase3.deposit(POOL_ID_SBF, farmingInfo.amount, farmingInfo.userAddr);
            farmingInfo.farmingPhaseAmount = 3;
            needMigration = true;
        }
        if (block.timestamp-farmingInfo.timestamp>60*ONE_DAY&&farmingInfo.farmingPhaseAmount<4) {
            farmingPhase4.deposit(POOL_ID_SBF, farmingInfo.amount, farmingInfo.userAddr);
            farmingInfo.farmingPhaseAmount = 4;
            needMigration = true;
        }
        require(needMigration, "no need to migration");
    }

    function batchMigrateSBFPoolAgeFarming(uint256[] memory _farmingIdxs) public {
        for(uint256 idx=0;idx<_farmingIdxs.length;idx++){
            migrateSBFPoolAgeFarming(_farmingIdxs[idx]);
        }
    }

    function stopFarming() public onlyOwner {
        farmingPhase1.stopFarmingPhase();
        farmingPhase2.stopFarmingPhase();
        farmingPhase3.stopFarmingPhase();
        farmingPhase4.stopFarmingPhase();
    }
}
