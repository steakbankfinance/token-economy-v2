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
            100,
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
        assert.equal(endBlock, "200", "wrong endBlock");
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

        await time.advanceBlock();
        let player0PendingSBF = await farmingCenterInst.pendingSBF(0, player0);
        assert.equal(player0PendingSBF, web3.utils.toBN(1e18).mul(web3.utils.toBN(3)).toString(), "wrong player0PendingSBF");

        let player0FarmingSpeed = await farmingCenterInst.farmingSpeed(0, player0);
        assert.equal(player0FarmingSpeed, web3.utils.toBN(1e18).mul(web3.utils.toBN(3)).toString(), "wrong farming speed");

        await farmingCenterInst.depositSBFPool(web3.utils.toBN(1e18).mul(web3.utils.toBN(10)), {from: player0});
        await time.advanceBlock();

        player0FarmingSpeed = await farmingCenterInst.farmingSpeed(0, player0);
        assert.equal(player0FarmingSpeed, web3.utils.toBN(1e18).mul(web3.utils.toBN(3)).toString(), "wrong farming speed");

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
        assert.equal(player0FarmingSpeed, web3.utils.toBN(1e18).mul(web3.utils.toBN(12)).toString(), "wrong farmingSpeed");

        const farmingPhase1Inst = await FarmingPhase1.deployed();
        const farmingPhase2Inst = await FarmingPhase2.deployed();
        const farmingPhase3Inst = await FarmingPhase3.deployed();
        const farmingPhase4Inst = await FarmingPhase4.deployed();

        let lpSupply = await farmingPhase2Inst.lpSupply(0);
        assert.equal(lpSupply, web3.utils.toBN(1e18).mul(web3.utils.toBN(20)).toString(), "wrong lpSupply");

        await time.increase(30);
        await farmingCenterInst.migrateSBFPoolAgeFarming(0, {from: ownerAcc});
        await farmingCenterInst.migrateSBFPoolAgeFarming(1, {from: ownerAcc});
        player0FarmingSpeed = await farmingCenterInst.farmingSpeed(0, player0);
        assert.equal(player0FarmingSpeed, web3.utils.toBN(1e18).mul(web3.utils.toBN(21)).toString(), "wrong farmingSpeed");

        await time.increase(30);
        await farmingCenterInst.migrateSBFPoolAgeFarming(0, {from: ownerAcc});
        await farmingCenterInst.migrateSBFPoolAgeFarming(1, {from: ownerAcc});
        player0FarmingSpeed = await farmingCenterInst.farmingSpeed(0, player0);
        assert.equal(player0FarmingSpeed, web3.utils.toBN(1e18).mul(web3.utils.toBN(30)).toString(), "wrong farmingSpeed");

        const{userAddr,poolID,amount,timestamp,farmingPhaseAmount} = await farmingCenterInst.farmingInfoMap(0);
        assert.equal(farmingPhaseAmount, "4", "wrong lpSupply");

        lpSupply = await farmingPhase2Inst.lpSupply(0);
        assert.equal(lpSupply, web3.utils.toBN(1e18).mul(web3.utils.toBN(20)).toString(), "wrong lpSupply");
        lpSupply = await farmingPhase3Inst.lpSupply(0);
        assert.equal(lpSupply, web3.utils.toBN(1e18).mul(web3.utils.toBN(20)).toString(), "wrong lpSupply");
        lpSupply = await farmingPhase4Inst.lpSupply(0);
        assert.equal(lpSupply, web3.utils.toBN(1e18).mul(web3.utils.toBN(20)).toString(), "wrong lpSupply");

        await farmingCenterInst.depositSBFPool(web3.utils.toBN(1e18).mul(web3.utils.toBN(10)), {from: player1});
        await farmingCenterInst.depositSBFPool(web3.utils.toBN(1e18).mul(web3.utils.toBN(10)), {from: player2});
        await time.advanceBlock();

        lpSupply = await farmingPhase1Inst.lpSupply(0);
        assert.equal(lpSupply, web3.utils.toBN(1e18).mul(web3.utils.toBN(40)).toString(), "wrong lpSupply");

        player0FarmingSpeed = await farmingCenterInst.farmingSpeed(0, player0);
        let player1FarmingSpeed = await farmingCenterInst.farmingSpeed(0, player1);
        let player2FarmingSpeed = await farmingCenterInst.farmingSpeed(0, player2);
        assert.equal(player0FarmingSpeed, web3.utils.toBN(1e17).mul(web3.utils.toBN(285)).toString(), "wrong farmingSpeed");
        assert.equal(player1FarmingSpeed, web3.utils.toBN(1e16).mul(web3.utils.toBN(75)).toString(), "wrong farmingSpeed");
        assert.equal(player2FarmingSpeed, web3.utils.toBN(1e16).mul(web3.utils.toBN(75)).toString(), "wrong farmingSpeed");

        await time.increase(30);
        await farmingCenterInst.batchMigrateSBFPoolAgeFarming([2,3], {from: ownerAcc});

        lpSupply = await farmingPhase2Inst.lpSupply(0);
        assert.equal(lpSupply, web3.utils.toBN(1e18).mul(web3.utils.toBN(40)).toString(), "wrong lpSupply");

        const aSBFInst = await aSBF.deployed();
        await aSBFInst.approve(FarmingCenter.address, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e10)),{from: player0});
        await farmingCenterInst.batchWithdrawSBFPool([0,1],{from: player0});
    });
    it('Test LBNB/BNB Pool Deposit and Withdraw', async () => {
        const farmingCenterInst = await FarmingCenter.deployed();
        const LBNB2BNBLPTokenInst = await LBNB2BNBLPToken.deployed();
        const ownerAcc = accounts[0];
        const player0 = accounts[2];
        const player1 = accounts[3];
        const player2 = accounts[4];

        await LBNB2BNBLPTokenInst.transfer(player0, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e6)), {from: ownerAcc});
        await LBNB2BNBLPTokenInst.transfer(player1, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e6)), {from: ownerAcc});
        await LBNB2BNBLPTokenInst.transfer(player2, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e6)), {from: ownerAcc});

        await LBNB2BNBLPTokenInst.approve(FarmingCenter.address, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e10)), {from: player0});
        await LBNB2BNBLPTokenInst.approve(FarmingCenter.address, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e10)), {from: player1});
        await LBNB2BNBLPTokenInst.approve(FarmingCenter.address, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e10)), {from: player2});

        let farmingIdx0 = await farmingCenterInst.farmingIdx();
        await farmingCenterInst.depositLBNB2BNBPool(web3.utils.toBN(1e18).mul(web3.utils.toBN(10)), {from: player0});

        await time.advanceBlock();

        let player0PendingSBF = await farmingCenterInst.pendingSBF(1, player0);
        assert.equal(player0PendingSBF, web3.utils.toBN(1e18).mul(web3.utils.toBN(40)).toString(), "wrong player0PendingSBF");

        let farmingIdx1 = await farmingCenterInst.farmingIdx();
        await farmingCenterInst.depositLBNB2BNBPool(web3.utils.toBN(1e18).mul(web3.utils.toBN(10)), {from: player0});
        await farmingCenterInst.depositLBNB2BNBPool(web3.utils.toBN(1e18).mul(web3.utils.toBN(10)), {from: player1});

        await time.advanceBlock();

        const aLBNB2BNBLPInst = await aLBNB2BNBLP.deployed();
        await aLBNB2BNBLPInst.approve(FarmingCenter.address, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e10)),{from: player0});
        await farmingCenterInst.batchWithdrawLBNB2BNBPool([farmingIdx0, farmingIdx1], {from: player0});
    });
    it('Test SBF/BUSD Pool Deposit and Withdraw', async () => {
        const farmingCenterInst = await FarmingCenter.deployed();
        const SBF2BUSDLPTokenInst = await SBF2BUSDLPToken.deployed();
        const ownerAcc = accounts[0];
        const player0 = accounts[2];
        const player1 = accounts[3];
        const player2 = accounts[4];

        await SBF2BUSDLPTokenInst.transfer(player0, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e6)), {from: ownerAcc});
        await SBF2BUSDLPTokenInst.transfer(player1, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e6)), {from: ownerAcc});
        await SBF2BUSDLPTokenInst.transfer(player2, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e6)), {from: ownerAcc});

        await SBF2BUSDLPTokenInst.approve(FarmingCenter.address, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e10)), {from: player0});
        await SBF2BUSDLPTokenInst.approve(FarmingCenter.address, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e10)), {from: player1});
        await SBF2BUSDLPTokenInst.approve(FarmingCenter.address, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e10)), {from: player2});

        let farmingIdx0 = await farmingCenterInst.farmingIdx();
        await farmingCenterInst.depositSBF2BUSDPool(web3.utils.toBN(1e18).mul(web3.utils.toBN(10)), {from: player0});

        await time.advanceBlock();

        let player0PendingSBF = await farmingCenterInst.pendingSBF(2, player0);
        assert.equal(player0PendingSBF, web3.utils.toBN(1e18).mul(web3.utils.toBN(21)).toString(), "wrong player0PendingSBF");

        let farmingIdx1 = await farmingCenterInst.farmingIdx();
        await farmingCenterInst.depositSBF2BUSDPool(web3.utils.toBN(1e18).mul(web3.utils.toBN(10)), {from: player0});
        await farmingCenterInst.depositSBF2BUSDPool(web3.utils.toBN(1e18).mul(web3.utils.toBN(10)), {from: player1});

        await time.advanceBlock();

        await time.increase(61);
        await farmingCenterInst.batchMigrateSBF2BUSDPoolAgeFarming([farmingIdx0, farmingIdx1], {from: player0});

        await time.advanceBlock();

        const aSBF2BUSDLPInst = await aSBF2BUSDLP.deployed();
        await aSBF2BUSDLPInst.approve(FarmingCenter.address, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e10)),{from: player0});
        await farmingCenterInst.batchWithdrawSBF2BUSDPool([farmingIdx0, farmingIdx1], {from: player0});
    });
    it('Test Stop Farming', async () => {
        const farmingCenterInst = await FarmingCenter.deployed();

        const ownerAcc = accounts[0];
        const player0 = accounts[2];
        const player1 = accounts[3];
        const player2 = accounts[4];

        await time.advanceBlockTo(180);

        await farmingCenterInst.harvest(0, {from: player0});
        await farmingCenterInst.harvest(0, {from: player1});
        await farmingCenterInst.harvest(0, {from: player2});

        await farmingCenterInst.harvest(1, {from: player0});
        await farmingCenterInst.harvest(1, {from: player1});
        await farmingCenterInst.harvest(1, {from: player2});

        await farmingCenterInst.harvest(2, {from: player0});
        await farmingCenterInst.harvest(2, {from: player1});
        await farmingCenterInst.harvest(2, {from: player2});

        await time.advanceBlockTo(190);
        await farmingCenterInst.stopFarming({from: ownerAcc});

        const farmingPhase1Inst = await FarmingPhase1.deployed();
        const sbfPerBlockPhase1 = await farmingPhase1Inst.sbfPerBlock();
        assert.equal(sbfPerBlockPhase1, "0", "wrong sbfPerBlock");

        const farmingPhase2Inst = await FarmingPhase2.deployed();
        const sbfPerBlockPhase2 = await farmingPhase2Inst.sbfPerBlock();
        assert.equal(sbfPerBlockPhase2, "0", "wrong sbfPerBlock");

        const farmingPhase3Inst = await FarmingPhase3.deployed();
        const sbfPerBlockPhase3 = await farmingPhase3Inst.sbfPerBlock();
        assert.equal(sbfPerBlockPhase3, "0", "wrong sbfPerBlock");

        const farmingPhase4Inst = await FarmingPhase4.deployed();
        const sbfPerBlockPhase4 = await farmingPhase4Inst.sbfPerBlock();
        assert.equal(sbfPerBlockPhase4, "0", "wrong sbfPerBlock");

        await time.advanceBlockTo(220);
        await farmingCenterInst.redeemSBF({from: ownerAcc});

        let player0FarmingIDs = await farmingCenterInst.getUserFarmingIdxs(0, player0);
        await farmingCenterInst.emergencyWithdrawSBF(player0FarmingIDs, {from: player0});
        player0FarmingIDs = await farmingCenterInst.getUserFarmingIdxs(1, player0);
        await farmingCenterInst.emergencyWithdrawLBNB2BNBLP(player0FarmingIDs, {from: player0});
        player0FarmingIDs = await farmingCenterInst.getUserFarmingIdxs(2, player0);
        await farmingCenterInst.emergencyWithdrawSBF2BUSDLP(player0FarmingIDs, {from: player0});

        let player1FarmingIDs = await farmingCenterInst.getUserFarmingIdxs(0, player1);
        await farmingCenterInst.emergencyWithdrawSBF(player1FarmingIDs, {from: player1});
        player1FarmingIDs = await farmingCenterInst.getUserFarmingIdxs(1, player1);
        await farmingCenterInst.emergencyWithdrawLBNB2BNBLP(player1FarmingIDs, {from: player1});
        player1FarmingIDs = await farmingCenterInst.getUserFarmingIdxs(2, player1);
        await farmingCenterInst.emergencyWithdrawSBF2BUSDLP(player1FarmingIDs, {from: player1});

        let player2FarmingIDs = await farmingCenterInst.getUserFarmingIdxs(0, player2);
        await farmingCenterInst.emergencyWithdrawSBF(player2FarmingIDs, {from: player2});
        player2FarmingIDs = await farmingCenterInst.getUserFarmingIdxs(1, player2);
        await farmingCenterInst.emergencyWithdrawLBNB2BNBLP(player2FarmingIDs, {from: player2});
        player2FarmingIDs = await farmingCenterInst.getUserFarmingIdxs(2, player2);
        await farmingCenterInst.emergencyWithdrawSBF2BUSDLP(player2FarmingIDs, {from: player2});

        const sbfInst = await SBF.deployed();
        const LBNB2BNBLPInst = await LBNB2BNBLPToken.deployed();
        const SBF2BUSDLPInst = await SBF2BUSDLPToken.deployed();

        const farmingCenterSBFBalance = await sbfInst.balanceOf(FarmingCenter.address);
        const farmingCenterLBNB2BNBLPBalance = await LBNB2BNBLPInst.balanceOf(FarmingCenter.address);
        const farmingCenterSBF2BUSDLPBalance = await SBF2BUSDLPInst.balanceOf(FarmingCenter.address);

        assert.equal(farmingCenterSBFBalance, "0", "wrong balance");
        assert.equal(farmingCenterLBNB2BNBLPBalance, "0", "wrong balance");
        assert.equal(farmingCenterSBF2BUSDLPBalance, "0", "wrong balance");
    });
});
