const SBF = artifacts.require("SBF");
const SBF2BUSDLPToken = artifacts.require("SBF2BUSDLPToken");
const LBNB2BNBLPToken = artifacts.require("LBNB2BNBLPToken");

const aSBF = artifacts.require("aSBF");
const aLBNB2BNBLP = artifacts.require("aLBNB2BNBLP");
const aSBF2BUSDLP = artifacts.require("aSBF2BUSDLP");

const FarmingPhase1 = artifacts.require("FarmingPhase1");
const FarmingPhase2 = artifacts.require("FarmingPhase2");
const FarmingPhase3 = artifacts.require("FarmingPhase3");
const FarmingPhase4 = artifacts.require("FarmingPhase4");

const FarmingCenter = artifacts.require("FarmingCenter");

const Web3 = require('web3');
const truffleAssert = require('truffle-assertions');
const { expectRevert, time } = require('@openzeppelin/test-helpers');
const web3 = new Web3(new Web3.providers.HttpProvider('http://localhost:8545'));

contract('SteakBank Contract', (accounts) => {
    it('Test Farming Pool', async () => {
        const farmingCenterInst = await FarmingCenter.deployed();
        const sbfInst = await SBF.deployed();

        await sbfInst.approve(FarmingCenter.address, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e10)), {from: accounts[0]});
        await farmingCenterInst.initPools(
            [30,40,30],
            [0,40,30],
            [90,90,90],
            {from: accounts[0]}
        );

        await farmingCenterInst.startFarmingPeriod(
            1000,
            100,
            web3.utils.toBN(100).mul(web3.utils.toBN(1e18)),
            {from: accounts[0]}
        );

        const farmingPhase1Inst = await FarmingPhase1.deployed();

        const poolLength = await farmingPhase1Inst.poolLength();
        assert.equal(poolLength, "3", "wrong pool length");

        const sbfAddr = await farmingPhase1Inst.sbf();
        assert.equal(sbfAddr, SBF.address, "wrong sbf address");

        const startBlock = await farmingPhase1Inst.startBlock();
        assert.equal(startBlock, "100", "wrong startBlock");

        const endBlock = await farmingPhase1Inst.endBlock();
        assert.equal(endBlock, "1100", "wrong endBlock");
    });
    it('Test SBF Pool Deposit and Withdraw', async () => {
        const farmingCenterInst = await FarmingCenter.deployed();
        const sbfInst = await SBF.deployed();
        const ownerAcc = accounts[0];
        const player0 = accounts[2];
        const player1 = accounts[3];
        const player2 = accounts[4];

        await sbfInst.transfer(player0, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e6)),{from: ownerAcc});
        await sbfInst.transfer(player1, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e6)),{from: ownerAcc});
        await sbfInst.transfer(player2, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e6)),{from: ownerAcc});

        await sbfInst.approve(FarmingCenter.address, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e10)), {from: player0});
        await sbfInst.approve(FarmingCenter.address, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e10)), {from: player1});
        await sbfInst.approve(FarmingCenter.address, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e10)), {from: player2});

        await farmingCenterInst.depositSBFPool(web3.utils.toBN(1e18).mul(web3.utils.toBN(10)), {from: player0});

        await time.advanceBlockTo(100);

        let player0FarmingSpeed = await farmingCenterInst.farmingSpeed(0, player0);
        assert.equal(player0FarmingSpeed, web3.utils.toBN(1e18).mul(web3.utils.toBN(10)).toString(), "wrong farming speed");

        await farmingCenterInst.depositSBFPool(web3.utils.toBN(1e18).mul(web3.utils.toBN(10)), {from: player0});
        await time.advanceBlock();

        player0FarmingSpeed = await farmingCenterInst.farmingSpeed(0, player0);
        assert.equal(player0FarmingSpeed, web3.utils.toBN(1e18).mul(web3.utils.toBN(10)).toString(), "wrong farming speed");

        await time.increase(10);
        await farmingCenterInst.migrateSBFPoolAgeFarming(0, {from: ownerAcc});
        await farmingCenterInst.migrateSBFPoolAgeFarming(1, {from: ownerAcc});

        try {
            await farmingCenterInst.migrateSBFPoolAgeFarming(2, {from: ownerAcc});
            assert.fail();
        } catch (error) {
            assert.ok(error.toString().includes("empty farming info"));
        }

        await time.advanceBlock();

        player0FarmingSpeed = await farmingCenterInst.farmingSpeed(0, player0);
        assert.equal(player0FarmingSpeed, web3.utils.toBN(1e18).mul(web3.utils.toBN(40)).toString(), "wrong farmingSpeed");

        const farmingPhase2Inst = await FarmingPhase2.deployed();
        const farmingPhase3Inst = await FarmingPhase3.deployed();
        const farmingPhase4Inst = await FarmingPhase4.deployed();

        let lpSupply = await farmingPhase2Inst.lpSupply(0);
        assert.equal(lpSupply, web3.utils.toBN(1e18).mul(web3.utils.toBN(20)).toString(), "wrong lpSupply");

        await time.increase(30);
        await farmingCenterInst.migrateSBFPoolAgeFarming(0, {from: ownerAcc});
        await farmingCenterInst.migrateSBFPoolAgeFarming(1, {from: ownerAcc});
        player0FarmingSpeed = await farmingCenterInst.farmingSpeed(0, player0);
        assert.equal(player0FarmingSpeed, web3.utils.toBN(1e18).mul(web3.utils.toBN(70)).toString(), "wrong farmingSpeed");

        await time.increase(30);
        await farmingCenterInst.migrateSBFPoolAgeFarming(0, {from: ownerAcc});
        await farmingCenterInst.migrateSBFPoolAgeFarming(1, {from: ownerAcc});
        player0FarmingSpeed = await farmingCenterInst.farmingSpeed(0, player0);
        assert.equal(player0FarmingSpeed, web3.utils.toBN(1e18).mul(web3.utils.toBN(100)).toString(), "wrong farmingSpeed");

        const{userAddr,poolID,amount,timestamp,farmingPhaseAmount} = await farmingCenterInst.farmingInfoMap(0);
        assert.equal(farmingPhaseAmount, "4", "wrong lpSupply");

        lpSupply = await farmingPhase2Inst.lpSupply(0);
        assert.equal(lpSupply, web3.utils.toBN(1e18).mul(web3.utils.toBN(20)).toString(), "wrong lpSupply");
        lpSupply = await farmingPhase3Inst.lpSupply(0);
        assert.equal(lpSupply, web3.utils.toBN(1e18).mul(web3.utils.toBN(20)).toString(), "wrong lpSupply");
        lpSupply = await farmingPhase4Inst.lpSupply(0);
        assert.equal(lpSupply, web3.utils.toBN(1e18).mul(web3.utils.toBN(20)).toString(), "wrong lpSupply");
    });
});
