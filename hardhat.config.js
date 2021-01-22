const { BigNumber } = require("@ethersproject/bignumber");

require("@nomiclabs/hardhat-ethers");

require("hardhat-deploy");

const networks = {
    hardhat: {
        blockGasLimit: 200000000,
        allowUnlimitedContractSize: true,
        chainId: 31337
    },
    coverage: {
        url: "http://127.0.0.1:8555",
        blockGasLimit: 200000000,
        allowUnlimitedContractSize: true
    },
    localhost: {
        url: "http://127.0.0.1:8545",
        blockGasLimit: 200000000,
        allowUnlimitedContractSize: true,
        chainId: 31337
    }
};

if (process.env.HDWALLET_MNEMONIC) {
    if (process.env.VELAS_TEST_RPC) {
        networks.vlxtest = {
            url: process.env.VELAS_TEST_RPC,
            accounts: {
                mnemonic: process.env.HDWALLET_MNEMONIC
            }
        };
    }
    if (process.env.VELAS_RPC) {
        networks.vlxmain = {
            url: process.env.VELAS_RPC,
            accounts: {
                mnemonic: process.env.HDWALLET_MNEMONIC
            }
        };
    }
    // else {
    //     networks.fork = {
    //         url: "http://127.0.0.1:8545"
    //     };
    // }
} else {
    console.warn("No infura or hdwallet available for testnets");
}

if (process.env.USE_BUIDLER_EVM_ACCOUNTS) {
    networks.hardhat.accounts = process.env.USE_BUIDLER_EVM_ACCOUNTS.split(/\s+/).map(
        privateKey => ({
            privateKey,
            balance: BigNumber.from("10").pow(25).toHexString()
        })
    );
}

task("accounts", "Prints the list of accounts", async (_, { ethers }) => {
    const walletMnemonic = ethers.Wallet.fromMnemonic(process.env.HDWALLET_MNEMONIC);
    console.log(walletMnemonic.address);
});

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
    solidity: {
        version: "0.6.12",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200
            }
        }
    },
    namedAccounts: {
        deployer: {
            default: 0
        }
    },
    networks
};
