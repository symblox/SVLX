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

    await deploy("SVLX", {
        from: deployer,
        proxy: "initialize"
    });
};
