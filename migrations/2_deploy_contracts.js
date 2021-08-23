const SBF = artifacts.require("SBF");
const SBF2BUSDLPToken = artifacts.require("SBF2BUSDLPToken");
const LBNB2BNBLPToken = artifacts.require("LBNB2BNBLPToken");
const aSBF = artifacts.require("aSBF");

const FarmingPhase1 = artifacts.require("FarmingPhase1");
const FarmingPhase2 = artifacts.require("FarmingPhase2");
const FarmingPhase3 = artifacts.require("FarmingPhase3");
const FarmingPhase4 = artifacts.require("FarmingPhase4");

const FarmingCenter = artifacts.require("FarmingCenter");

module.exports = function (deployer, network, accounts) {
  deployerAcc = accounts[0];
  taxVault = accounts[1];
  deployer.deploy(SBF, deployerAcc).then(async () => {
    await deployer.deploy(LBNB2BNBLPToken, deployerAcc);
    await deployer.deploy(SBF2BUSDLPToken, deployerAcc);

    await deployer.deploy(FarmingPhase1);
    await deployer.deploy(FarmingPhase2);
    await deployer.deploy(FarmingPhase3);
    await deployer.deploy(FarmingPhase4);

    await deployer.deploy(FarmingCenter);
    await deployer.deploy(aSBF, FarmingCenter.address);

    const farmingCenterInst = await FarmingCenter.deployed();

    await farmingCenterInst.initialize(deployerAcc,
        aSBF.address,
        SBF.address,
        LBNB2BNBLPToken.address,
        SBF2BUSDLPToken.address,
        FarmingPhase1.address,
        FarmingPhase2.address,
        FarmingPhase3.address,
        FarmingPhase4.address,
        taxVault);
  });
};
