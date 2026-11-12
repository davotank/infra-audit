import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const { AMOY_RPC_URL, DEPLOYER_PRIVATE_KEY } = process.env;

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: { optimizer: { enabled: true, runs: 200 }, evmVersion: "paris" },
  },
  networks: {
    amoy: {
      url: AMOY_RPC_URL ?? "https://rpc-amoy.polygon.technology",
      chainId: 80002,
      accounts: DEPLOYER_PRIVATE_KEY ? [DEPLOYER_PRIVATE_KEY] : [],
    },
  },
};

export default config;
