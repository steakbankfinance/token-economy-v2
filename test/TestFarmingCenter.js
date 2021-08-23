const SBF = artifacts.require("SBF");
const SBF2BUSDLPToken = artifacts.require("SBF2BUSDLPToken");
const LBNB2BNBLPToken = artifacts.require("LBNB2BNBLPToken");
const aSBF = artifacts.require("aSBF");

const FarmingPhase1 = artifacts.require("FarmingPhase1");
const FarmingPhase2 = artifacts.require("FarmingPhase2");
const FarmingPhase3 = artifacts.require("FarmingPhase3");
const FarmingPhase4 = artifacts.require("FarmingPhase4");

const FarmingCenter = artifacts.require("FarmingCenter");

const Web3 = require('web3');
const truffleAssert = require('truffle-assertions');
const web3 = new Web3(new Web3.providers.HttpProvider('http://localhost:8545'));

contract('SteakBank Contract', (accounts) => {
    it('Test Farming Pool', async () => {
        const farmingCenterInst = await FarmingCenter.deployed();
        const sbfInst = await SBF.deployed();

        await sbfInst.approve(FarmingCenter.address, web3.utils.toBN(1e18).mul(web3.utils.toBN(1e10)), {from: accounts[0]});
        await farmingCenterInst.initPools(
            [30,40,30],
            [0,40,30],
            [80,80,80],
            {from: accounts[0]}
        );

        await farmingCenterInst.startFarmingPeriod(
            1000,
            100,
            web3.utils.toBN(100).mul(web3.utils.toBN(1e18)),
            {from: accounts[0]}
        );
    });
});