const {ethers, deployments} = require("hardhat")

async function run() {
    const [signer] = await ethers.getSigners()
    const deployer = signer.address
    console.log({deployer})

    const { deploy } = deployments;

    await deploy("SVLX", {
        from: deployer,
        proxy: true
    });
}

run()