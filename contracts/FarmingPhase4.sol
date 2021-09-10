pragma solidity 0.6.12;

import "./lib/Ownable.sol";
import "./interface/IFarm.sol";

import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";

contract FarmingPhase4 is Ownable, IFarm {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    uint256 constant public BLOCKS_PER_DAY = 28800;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        IBEP20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accSBFPerShare;
        uint256 maxTaxPercent;
        uint256 miniTaxFreeDay;
    }

    uint256 constant public REWARD_CALCULATE_PRECISION = 1e12;

    bool public initialized;

    IBEP20 public sbf;

    address public taxVault;
    uint256 public sbfPerBlock;
    uint256 public totalAllocPoint;
    uint256 public startBlock;
    uint256 public endBlock;
    mapping(uint256 => uint256) lpSupplyMap;

    PoolInfo[] public poolInfo;
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, uint256 reward, uint256 taxAmount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, uint256 reward, uint256 taxAmount);

    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor() public {}

    function initialize(address _owner, IBEP20 _sbf, address _taxVault) override external {
        require(!initialized, "already initialized");
        initialized = true;

        super.initializeOwner(_owner);
        sbf = _sbf;
        taxVault = _taxVault;
    }

    function startFarmingPeriod(uint256 farmingPeriod, uint256 startHeight, uint256 sbfRewardPerBlock) override external onlyOwner {
        require(block.number <= startHeight, "Start height must be in the future");
        require(sbfRewardPerBlock > 0, "sbfRewardPerBlock must be larger than 0");
        require(farmingPeriod > 0, "farmingPeriod must be larger than 0");

        massUpdatePools();

        uint256 totalSBFAmount = farmingPeriod.mul(sbfRewardPerBlock);
        sbf.safeTransferFrom(msg.sender, address(this), totalSBFAmount);

        sbfPerBlock = sbfRewardPerBlock;
        startBlock = startHeight;
        endBlock = startHeight.add(farmingPeriod);

        for (uint256 pid = 0; pid < poolInfo.length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            pool.lastRewardBlock = startHeight;
        }
    }

    function addPool(uint256 _allocPoint, IBEP20 _lpToken, uint256 _maxTaxPercent, uint256 _miniTaxFreeDay, bool _withUpdate) override external onlyOwner {
        for (uint256 pid = 0; pid < poolInfo.length; ++pid) {
            PoolInfo memory pool = poolInfo[pid];
            require(pool.lpToken!=_lpToken, "duplicated pool");
        }
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        lpToken: _lpToken,
        allocPoint: _allocPoint,
        lastRewardBlock: lastRewardBlock,
        accSBFPerShare: 0,
        maxTaxPercent: _maxTaxPercent,
        miniTaxFreeDay: _miniTaxFreeDay
        }));
    }

    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) override external onlyOwner {
        require(_pid < poolInfo.length, "invalid pool id");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        if (prevAllocPoint != _allocPoint) {
            poolInfo[_pid].allocPoint = _allocPoint;
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
        }
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= endBlock) {
            return _to.sub(_from);
        } else if (_from >= endBlock) {
            return 0;
        } else {
            return endBlock.sub(_from);
        }
    }

    function pendingSBF(uint256 _pid, address _user) override external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSBFPerShare = pool.accSBFPerShare;
        uint256 lpSupply = lpSupplyMap[_pid];
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 sbfReward = multiplier.mul(sbfPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accSBFPerShare = accSBFPerShare.add(sbfReward.mul(REWARD_CALCULATE_PRECISION).div(lpSupply));
        }
        return user.amount.mul(accSBFPerShare).div(REWARD_CALCULATE_PRECISION).sub(user.rewardDebt);
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 _pid) public {
        require(_pid < poolInfo.length, "invalid pool id");
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = lpSupplyMap[_pid];
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 sbfReward = multiplier.mul(sbfPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accSBFPerShare = pool.accSBFPerShare.add(sbfReward.mul(REWARD_CALCULATE_PRECISION).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    function deposit(uint256 _pid, uint256 _amount, address _userAddr) override external onlyOwner {
        require(_pid < poolInfo.length, "invalid pool id");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_userAddr];
        updatePool(_pid);
        uint256 reward;
        uint256 taxAmount;
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accSBFPerShare).div(REWARD_CALCULATE_PRECISION).sub(user.rewardDebt);

            if (pending > 0) {
                (reward, taxAmount) = rewardSBF(_pid, _userAddr, pending);
            }
        }
        if (_amount > 0) {
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accSBFPerShare).div(REWARD_CALCULATE_PRECISION);
        lpSupplyMap[_pid] = lpSupplyMap[_pid].add(_amount);
        emit Deposit(_userAddr, _pid, _amount, reward, taxAmount);
    }

    function withdraw(uint256 _pid, uint256 _amount, address _userAddr) override external onlyOwner {
        require(_pid < poolInfo.length, "invalid pool id");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_userAddr];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accSBFPerShare).div(REWARD_CALCULATE_PRECISION).sub(user.rewardDebt);
        uint256 reward;
        uint256 taxAmount;
        if (pending > 0) {
            (reward, taxAmount) = rewardSBF(_pid, _userAddr, pending);
        }

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accSBFPerShare).div(REWARD_CALCULATE_PRECISION);
        lpSupplyMap[_pid] = lpSupplyMap[_pid].sub(_amount);
        emit Withdraw(_userAddr, _pid, _amount, reward, taxAmount);
    }

    function emergencyWithdraw(uint256 _pid, uint256 _amount, address _userAddr) override external onlyOwner {
        require(_pid < poolInfo.length, "invalid pool id");
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_userAddr];
        emit EmergencyWithdraw(_userAddr, _pid, _amount);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accSBFPerShare).div(REWARD_CALCULATE_PRECISION);
        lpSupplyMap[_pid] = lpSupplyMap[_pid].sub(_amount);
    }

    function redeemSBF(address recipient) override external onlyOwner {
        uint256 balance = sbf.balanceOf(address(this));
        sbf.safeTransfer(recipient, balance);
    }

    function lpSupply(uint256 _pid) override external view returns (uint256) {
        return lpSupplyMap[_pid];
    }

    function rewardSBF(uint256 _pid, address _to, uint256 _amount) internal returns (uint256, uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_to];
        uint256 taxAmount = 0;
        uint256 rewardAmount = _amount;
        if (block.number-startBlock<pool.miniTaxFreeDay.mul(BLOCKS_PER_DAY)) {
            uint256 taxRatePercent = pool.maxTaxPercent.sub((block.number-startBlock).mul(pool.maxTaxPercent).div(pool.miniTaxFreeDay.mul(BLOCKS_PER_DAY)));
            taxAmount = taxRatePercent.mul(_amount).div(100);
            rewardAmount = _amount.sub(taxAmount);
        }
        sbf.safeTransfer(_to, rewardAmount);
        sbf.safeTransfer(taxVault, taxAmount);
        return (rewardAmount, taxAmount);
    }

    function stopFarmingPhase() override external onlyOwner {
        massUpdatePools();
        sbfPerBlock = 0;
    }
}
