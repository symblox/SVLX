const debug = require("debug")("ptv3:deploy.js");

module.exports = async hardhat => {
    const { getNamedAccounts, deployments, getChainId } = hardhat;
    const [signer] = await ethers.getSigners();

    let { deployer, adminAccount } = await getNamedAccounts();
    debug({ deployer });

    if (!adminAccount) {
        debug("  Using deployer as adminAccount;");

        adminAccount = signer.address;
    }
    debug("\n  adminAccount:  ", adminAccount);

    const { deploy } = deployments;

    const svlxContract = await deploy("SVLX", {
        from: deployer,
        proxy: "initialize"
    });
    debug("\n  svlxContract:  ", svlxContract.address);
    // Add the default pool
    const chainId = parseInt(await getChainId(), 10);
    const STAKE_POOLS = {
        106: "0x7f7697E82be5d7F41De6b283Ca562e4D79a4F74a",
        111: "0x267Ec0079043B43930a1d671FB98fD19FdCaF449"
    };
    debug("\n  Add staking pool:  ", STAKE_POOLS[chainId]);
    const svlx = await ethers.getContractAt("SVLX", svlxContract.address, signer);
    await svlx.addPool(STAKE_POOLS[chainId]);

    console.log(`Deployed SVLX ${svlxContract.address}\nAdded stake pool ${STAKE_POOLS[chainId]}`);
};
