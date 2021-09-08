pragma solidity 0.6.12;
//pragma experimental ABIEncoderV2;

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

    //TODO change to 86400 for mainnet
    uint256 constant public ONE_DAY = 1; // 86400

    bool public initialized;
    bool public pool_initialized;

    address public aSBF;
    address public aLBNB2BNBLP;
    address public aSBF2BUSDLP;

    uint256 public farmingIdx;
    mapping(uint256 => FarmingInfo) public farmingInfoMap;
    mapping(address => mapping(uint256 => uint256[])) public userToFarmingIDsMap;
    mapping(uint256 => uint256) public poolAllocPoints;

    IBEP20 public sbf;
    IBEP20 public lpLBNB2BNB;
    IBEP20 public lpSBF2BUSD;

    IFarm[4] public farmingPhases;

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

        farmingPhases[0] = _farmingPhase1;
        farmingPhases[1] = _farmingPhase2;
        farmingPhases[2] = _farmingPhase3;
        farmingPhases[3] = _farmingPhase4;

        for(uint256 i=0;i<4;i++){
            farmingPhases[i].initialize(address(this), _sbf, _taxVault);
        }
    }

    function initPools(uint256[] calldata _allocPoints, uint256[] calldata _maxTaxPercents, uint256[] calldata _miniTaxFreeDays, bool _withUpdate) external onlyOwner {
        require(initialized, "farm is not initialized");
        require(!pool_initialized, "farms are already initialized");
        pool_initialized = true;

        require(_allocPoints.length==3&&_maxTaxPercents.length==3&&_miniTaxFreeDays.length==3, "wrong array length");

        IBEP20[3] memory LPs = [sbf, lpLBNB2BNB, lpSBF2BUSD];
        for(uint256 i=0;i<3;i++){
            poolAllocPoints[i] = _allocPoints[i];
            for(uint256 j=0;j<4;j++){
                farmingPhases[j].addPool(_allocPoints[i], LPs[i],_maxTaxPercents[i],_miniTaxFreeDays[i],_withUpdate);
            }
        }
    }

    function startFarmingPeriod(uint256 _farmingPeriod, uint256 _startHeight, uint256 _sbfRewardPerBlock) public onlyOwner {
        require(pool_initialized, "farm pools are not initialized");

        startBlock = _startHeight;
        endBlock = _startHeight.add(_farmingPeriod);

        uint256 totalSBFAmount = _farmingPeriod.mul(_sbfRewardPerBlock);
        sbf.safeTransferFrom(msg.sender, address(this), totalSBFAmount);

        sbf.approve(address(farmingPhases[0]), totalSBFAmount.mul(10).div(100));
        sbf.approve(address(farmingPhases[1]), totalSBFAmount.mul(30).div(100));
        sbf.approve(address(farmingPhases[2]), totalSBFAmount.mul(30).div(100));
        sbf.approve(address(farmingPhases[3]), totalSBFAmount.mul(30).div(100));

        farmingPhases[0].startFarmingPeriod(_farmingPeriod, _startHeight, _sbfRewardPerBlock.mul(10).div(100));
        farmingPhases[1].startFarmingPeriod(_farmingPeriod, _startHeight, _sbfRewardPerBlock.mul(30).div(100));
        farmingPhases[2].startFarmingPeriod(_farmingPeriod, _startHeight, _sbfRewardPerBlock.mul(30).div(100));
        farmingPhases[3].startFarmingPeriod(_farmingPeriod, _startHeight, _sbfRewardPerBlock.mul(30).div(100));

        sbfRewardPerBlock = _sbfRewardPerBlock;
    }

    /*
     pid 0 -> sbf pool
     pid 1 -> lbnb2bnb pool
     pid 2 -> sbf2busd pool
    */
    function set(uint256 _pid, uint256 _allocPoints, bool _withUpdate) public onlyOwner {
        poolAllocPoints[_pid] = _allocPoints;
        for(uint256 i=0;i<4;i++){
            farmingPhases[i].set(_pid, _allocPoints, _withUpdate);
        }
    }

    function redeemSBF() public onlyOwner {
        require(block.number>=endBlock, "farming is not end");
        for(uint256 i=0;i<4;i++){
            farmingPhases[i].redeemSBF(msg.sender);
        }
    }

    function pendingSBF(uint256 _pid, address _user) external view returns (uint256) {
        return farmingPhases[0].pendingSBF(_pid, _user).
        add(farmingPhases[1].pendingSBF(_pid, _user)).
        add(farmingPhases[2].pendingSBF(_pid, _user)).
        add(farmingPhases[3].pendingSBF(_pid, _user));
    }

    function getUserFarmingIdxs(uint256 _pid, address _user) external view returns(uint256[] memory) {
        return userToFarmingIDsMap[_user][_pid];
    }

    function farmingSpeed(uint256 _pid, address _user) external view returns (uint256) {
        uint256[] memory farmingIdxs = userToFarmingIDsMap[_user][_pid];
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
        if (farmingPhases[3].lpSupply(_pid)!=0) {
            totalPhaseAmount = totalPhaseAmount.add(accumulatePhaseAmount.mul(30).mul(poolSBFRewardPerBlock).div(farmingPhases[3].lpSupply(_pid)));
        }

        accumulatePhaseAmount = accumulatePhaseAmount.add(phaseAmountArray[2]);
        if (farmingPhases[2].lpSupply(_pid)!=0) {
            totalPhaseAmount = totalPhaseAmount.add(accumulatePhaseAmount.mul(30).mul(poolSBFRewardPerBlock).div(farmingPhases[2].lpSupply(_pid)));
        }

        accumulatePhaseAmount = accumulatePhaseAmount.add(phaseAmountArray[1]);
        if (farmingPhases[1].lpSupply(_pid)!=0) {
            totalPhaseAmount = totalPhaseAmount.add(accumulatePhaseAmount.mul(30).mul(poolSBFRewardPerBlock).div(farmingPhases[1].lpSupply(_pid)));
        }

        accumulatePhaseAmount = accumulatePhaseAmount.add(phaseAmountArray[0]);
        if (farmingPhases[0].lpSupply(_pid)!=0) {
            totalPhaseAmount = totalPhaseAmount.add(accumulatePhaseAmount.mul(10).mul(poolSBFRewardPerBlock).div(farmingPhases[0].lpSupply(_pid)));
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
            userToFarmingIDsMap[msg.sender][POOL_ID_SBF].push(farmingIdx);
            farmingIdx++;
        }

        sbf.safeTransferFrom(address(msg.sender), address(this), _amount);

        farmingPhases[0].deposit(POOL_ID_SBF, _amount, msg.sender);
        IMintBurnToken(aSBF).mintTo(msg.sender, _amount);
    }

    function withdrawSBFPool(uint256 _amount, uint256 _farmingIdx) public {
        FarmingInfo storage farmingInfo = farmingInfoMap[_farmingIdx];
        require(farmingInfo.userAddr==msg.sender, "can't withdraw other farming");
        require(farmingInfo.poolID==POOL_ID_SBF, "pool id mismatch");
        require(farmingInfo.amount>=_amount, "withdraw amount too much");

        IBEP20(aSBF).transferFrom(msg.sender, address(this), _amount);
        IMintBurnToken(aSBF).burn(_amount);

        if (farmingInfo.farmingPhaseAmount >= 4) {
            farmingPhases[3].withdraw(POOL_ID_SBF, farmingInfo.amount, farmingInfo.userAddr);
        }
        if (farmingInfo.farmingPhaseAmount >= 3) {
            farmingPhases[2].withdraw(POOL_ID_SBF, farmingInfo.amount, farmingInfo.userAddr);
        }
        if (farmingInfo.farmingPhaseAmount >= 2) {
            farmingPhases[1].withdraw(POOL_ID_SBF, farmingInfo.amount, farmingInfo.userAddr);
        }
        farmingPhases[0].withdraw(POOL_ID_SBF, _amount, farmingInfo.userAddr);

        if (farmingInfo.amount == _amount) {
            deleteUserFarmingIDs(_farmingIdx, POOL_ID_SBF);
            delete farmingInfoMap[_farmingIdx];
        } else {
            farmingInfo.amount = farmingInfo.amount.sub(_amount);
            farmingInfo.farmingPhaseAmount = 1;
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
            userToFarmingIDsMap[msg.sender][POOL_ID_LP_LBNB_BNB].push(farmingIdx);
            farmingIdx++;

            lpLBNB2BNB.safeTransferFrom(address(msg.sender), address(this), _amount);
        }

        farmingPhases[0].deposit(POOL_ID_LP_LBNB_BNB, _amount, msg.sender);
        farmingPhases[1].deposit(POOL_ID_LP_LBNB_BNB, _amount, msg.sender);
        farmingPhases[2].deposit(POOL_ID_LP_LBNB_BNB, _amount, msg.sender);
        farmingPhases[3].deposit(POOL_ID_LP_LBNB_BNB, _amount, msg.sender);
        
        IMintBurnToken(aLBNB2BNBLP).mintTo(msg.sender, _amount);
    }

    function withdrawLBNB2BNBPool(uint256 _amount, uint256 _farmingIdx) public {
        FarmingInfo storage farmingInfo = farmingInfoMap[_farmingIdx];
        require(farmingInfo.userAddr==msg.sender, "can't withdraw other farming");
        require(farmingInfo.poolID==POOL_ID_LP_LBNB_BNB, "pool id mismatch");
        require(_amount>0, "withdraw amount must be positive");
        require(farmingInfo.amount>=_amount, "withdraw amount too much");
        
        IBEP20(aLBNB2BNBLP).transferFrom(msg.sender, address(this), _amount);
        IMintBurnToken(aLBNB2BNBLP).burn(_amount);

        farmingPhases[3].withdraw(POOL_ID_LP_LBNB_BNB, _amount, msg.sender);
        farmingPhases[2].withdraw(POOL_ID_LP_LBNB_BNB, _amount, msg.sender);
        farmingPhases[1].withdraw(POOL_ID_LP_LBNB_BNB, _amount, msg.sender);
        farmingPhases[0].withdraw(POOL_ID_LP_LBNB_BNB, _amount, msg.sender);

        lpLBNB2BNB.safeTransfer(msg.sender, _amount);

        if (farmingInfo.amount == _amount) {
            deleteUserFarmingIDs(_farmingIdx, POOL_ID_LP_LBNB_BNB);
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
            userToFarmingIDsMap[msg.sender][POOL_ID_LP_SBF_BUSD].push(farmingIdx);
            farmingIdx++;
        }

        lpSBF2BUSD.safeTransferFrom(address(msg.sender), address(this), _amount);

        farmingPhases[0].deposit(POOL_ID_LP_SBF_BUSD, _amount, msg.sender);
        farmingPhases[1].deposit(POOL_ID_LP_SBF_BUSD, _amount, msg.sender);
        farmingPhases[2].deposit(POOL_ID_LP_SBF_BUSD, _amount, msg.sender);

        IMintBurnToken(aSBF2BUSDLP).mintTo(msg.sender, _amount);
    }

    function withdrawSBF2BUSDPool(uint256 _amount, uint256 _farmingIdx) public {
        FarmingInfo storage farmingInfo = farmingInfoMap[_farmingIdx];
        require(farmingInfo.userAddr==msg.sender, "can't withdraw other farming");
        require(farmingInfo.poolID==POOL_ID_LP_SBF_BUSD, "pool id mismatch");
        require(_amount>0, "withdraw amount must be positive");
        require(farmingInfo.amount>=_amount, "withdraw amount too much");

        IBEP20(aSBF2BUSDLP).transferFrom(msg.sender, address(this), _amount);
        IMintBurnToken(aSBF2BUSDLP).burn(_amount);

        if (farmingInfo.farmingPhaseAmount >= 4) {
            farmingPhases[3].withdraw(POOL_ID_LP_SBF_BUSD, farmingInfo.amount, msg.sender);
        }
        farmingPhases[2].withdraw(POOL_ID_LP_SBF_BUSD, _amount, msg.sender);
        farmingPhases[1].withdraw(POOL_ID_LP_SBF_BUSD, _amount, msg.sender);
        farmingPhases[0].withdraw(POOL_ID_LP_SBF_BUSD, _amount, msg.sender);

        lpSBF2BUSD.safeTransfer(msg.sender, _amount);

        if (farmingInfo.amount == _amount) {
            deleteUserFarmingIDs(_farmingIdx, POOL_ID_LP_SBF_BUSD);
            delete farmingInfoMap[_farmingIdx];
        } else {
            farmingInfo.amount = farmingInfo.amount.sub(_amount);
            farmingInfo.farmingPhaseAmount = 3;
            farmingInfo.timestamp = block.timestamp;
        }
    }

    function batchWithdrawSBF2BUSDPool(uint256[] memory _farmingIdxs) public {
        for(uint256 idx=0;idx<_farmingIdxs.length;idx++){
            FarmingInfo memory farmingInfo = farmingInfoMap[_farmingIdxs[idx]];
            withdrawSBF2BUSDPool(farmingInfo.amount, _farmingIdxs[idx]);
        }
    }

    function harvest(uint256 _pid) public {
        require(_pid==POOL_ID_SBF|| _pid==POOL_ID_LP_SBF_BUSD|| _pid==POOL_ID_LP_LBNB_BNB, "wrong pool id");
        for(uint256 i=0;i<4;i++){
            farmingPhases[i].deposit(_pid, 0, msg.sender);
        }
    }

    function emergencyWithdrawSBF(uint256[] memory _farmingIdxs) public {
        for(uint256 idx=0;idx<_farmingIdxs.length;idx++){
            FarmingInfo memory farmingInfo = farmingInfoMap[_farmingIdxs[idx]];
            require(farmingInfo.userAddr==msg.sender, "can't withdraw other farming");
            require(farmingInfo.poolID==POOL_ID_SBF, "pool id mismatch");
            sbf.safeTransfer(address(msg.sender), farmingInfo.amount);
            emit EmergencyWithdraw(msg.sender, POOL_ID_SBF, farmingInfo.amount);
            delete farmingInfoMap[_farmingIdxs[idx]];
            deleteUserFarmingIDs(_farmingIdxs[idx], POOL_ID_SBF);
        }
    }

    function emergencyWithdrawLBNB2BNBLP(uint256[] memory _farmingIdxs) public {
        for(uint256 idx=0;idx<_farmingIdxs.length;idx++){
            FarmingInfo memory farmingInfo = farmingInfoMap[_farmingIdxs[idx]];
            require(farmingInfo.userAddr==msg.sender, "can't withdraw other farming");
            require(farmingInfo.poolID==POOL_ID_LP_LBNB_BNB, "pool id mismatch");
            lpLBNB2BNB.safeTransfer(address(msg.sender), farmingInfo.amount);
            emit EmergencyWithdraw(msg.sender, POOL_ID_LP_LBNB_BNB, farmingInfo.amount);
            delete farmingInfoMap[_farmingIdxs[idx]];
            deleteUserFarmingIDs(_farmingIdxs[idx], POOL_ID_LP_LBNB_BNB);
        }
    }

    function emergencyWithdrawSBF2BUSDLP(uint256[] memory _farmingIdxs) public {
        for(uint256 idx=0;idx<_farmingIdxs.length;idx++){
            FarmingInfo memory farmingInfo = farmingInfoMap[_farmingIdxs[idx]];
            require(farmingInfo.userAddr==msg.sender, "can't withdraw other farming");
            require(farmingInfo.poolID==POOL_ID_LP_SBF_BUSD, "pool id mismatch");
            lpSBF2BUSD.safeTransfer(address(msg.sender), farmingInfo.amount);
            emit EmergencyWithdraw(msg.sender, POOL_ID_LP_SBF_BUSD, farmingInfo.amount);
            delete farmingInfoMap[_farmingIdxs[idx]];
            deleteUserFarmingIDs(_farmingIdxs[idx], POOL_ID_LP_SBF_BUSD);
        }
    }

    function deleteUserFarmingIDs(uint256 _idx, uint256 _pid) internal {
        uint256[] storage farmingIdxs = userToFarmingIDsMap[msg.sender][_pid];
        uint256 farmingIdxsLength = farmingIdxs.length;
        for (uint256 idx=0;idx<farmingIdxsLength;idx++){
            if (farmingIdxs[idx]==_idx) {
                farmingIdxs[idx]=farmingIdxs[farmingIdxsLength-1];
                break;
            }
        }
        farmingIdxs.pop();
    }

    function migrateSBFPoolAgeFarming(uint256 _farmingIdx) public {
        bool needMigration = false;
        FarmingInfo storage farmingInfo = farmingInfoMap[_farmingIdx];
        require(farmingInfo.userAddr!=address(0x0), "empty farming info");
        require(farmingInfo.poolID==POOL_ID_SBF, "pool id mismatch");
        if (block.timestamp-farmingInfo.timestamp>7*ONE_DAY&&farmingInfo.farmingPhaseAmount<2) {
            farmingPhases[1].deposit(POOL_ID_SBF, farmingInfo.amount, farmingInfo.userAddr);
            farmingInfo.farmingPhaseAmount = 2;
            needMigration = true;
        }
        if (block.timestamp-farmingInfo.timestamp>30*ONE_DAY&&farmingInfo.farmingPhaseAmount<3) {
            farmingPhases[2].deposit(POOL_ID_SBF, farmingInfo.amount, farmingInfo.userAddr);
            farmingInfo.farmingPhaseAmount = 3;
            needMigration = true;
        }
        if (block.timestamp-farmingInfo.timestamp>60*ONE_DAY&&farmingInfo.farmingPhaseAmount<4) {
            farmingPhases[3].deposit(POOL_ID_SBF, farmingInfo.amount, farmingInfo.userAddr);
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

    function migrateSBF2BUSDPoolAgeFarming(uint256 _farmingIdx) public {
        bool needMigration = false;
        FarmingInfo storage farmingInfo = farmingInfoMap[_farmingIdx];
        require(farmingInfo.userAddr!=address(0x0), "empty farming info");
        require(farmingInfo.poolID==POOL_ID_LP_SBF_BUSD, "pool id mismatch");
        if (block.timestamp-farmingInfo.timestamp>60*ONE_DAY&&farmingInfo.farmingPhaseAmount<4) {
            farmingPhases[3].deposit(POOL_ID_LP_SBF_BUSD, farmingInfo.amount, farmingInfo.userAddr);
            farmingInfo.farmingPhaseAmount = 4;
            needMigration = true;
        }
        require(needMigration, "no need to migration");
    }

    function batchMigrateSBF2BUSDPoolAgeFarming(uint256[] memory _farmingIdxs) public {
        for(uint256 idx=0;idx<_farmingIdxs.length;idx++){
            migrateSBF2BUSDPoolAgeFarming(_farmingIdxs[idx]);
        }
    }

    function stopFarming() public onlyOwner {
        for(uint256 i=0;i<4;i++){
            farmingPhases[i].stopFarmingPhase();
        }
    }
}
