import hre from "hardhat";
import { upgrades } from "@openzeppelin/hardhat-upgrades";

async function main() {
  // 1. Establish network connection & create upgrades instance for Hardhat 3
  const connection = await hre.network.create();
  const { ethers } = connection;
  const upgradesApi = await upgrades(hre, connection);

  const [deployer] = await ethers.getSigners();
  console.log("Deploying Remzik contracts with account:", deployer.address);

  // 2. Deploy RemzikIdentityRegistry as a UUPS Proxy
  console.log("\n[1/7] Deploying RemzikIdentityRegistry Proxy...");
  const IdentityRegistry = await ethers.getContractFactory(
    "RemzikIdentityRegistry",
  );
  const registry = await upgradesApi.deployProxy(
    IdentityRegistry,
    [], // 0 arguments because initialize() has no parameters
    {
      initializer: "initialize",
      kind: "uups",
    },
  );
  await registry.waitForDeployment();
  const registryAddress = await registry.getAddress();
  console.log("-> RemzikIdentityRegistry Proxy deployed to:", registryAddress);

  // 3. Deploy Price Oracle
  console.log("\n[2/7] Deploying PriceOracle...");
  const PriceOracle = await ethers.getContractFactory("PriceOracle");
  const priceOracle = await PriceOracle.deploy();
  await priceOracle.waitForDeployment();
  const priceOracleAddress = await priceOracle.getAddress();
  console.log("-> PriceOracle deployed to:", priceOracleAddress);

  // 4. Deploy Micro-Deployer Utility Contracts
  console.log("\n[3/7] Deploying TokenDeployer & GovDeployer...");
  const TokenDeployer = await ethers.getContractFactory("TokenDeployer");
  const tokenDeployer = await TokenDeployer.deploy();
  await tokenDeployer.waitForDeployment();
  const tokenDeployerAddress = await tokenDeployer.getAddress();
  console.log("-> TokenDeployer deployed to:", tokenDeployerAddress);

  const GovDeployer = await ethers.getContractFactory("GovDeployer");
  const govDeployer = await GovDeployer.deploy();
  await govDeployer.waitForDeployment();
  const govDeployerAddress = await govDeployer.getAddress();
  console.log("-> GovDeployer deployed to:", govDeployerAddress);

  // 5. Deploy Recovery Manager as a UUPS Proxy
  console.log("\n[4/7] Deploying RecoveryManager Proxy...");
  const RecoveryManager = await ethers.getContractFactory("RecoveryManager");
  const recoveryManager = await upgradesApi.deployProxy(
    RecoveryManager,
    [
      registryAddress,
      deployer.address, // admin passed to initialize()
    ],
    {
      initializer: "initialize",
      kind: "uups",
    },
  );
  await recoveryManager.waitForDeployment();
  const recoveryManagerAddress = await recoveryManager.getAddress();
  console.log("-> RecoveryManager Proxy deployed to:", recoveryManagerAddress);

  // 6. Deploy Asset Factory as a UUPS Proxy
  console.log("\n[5/7] Deploying AssetFactory Proxy...");
  const AssetFactory = await ethers.getContractFactory(
    "AssetFactoryUpgradeable",
  );
  const factory = await upgradesApi.deployProxy(
    AssetFactory,
    [
      registryAddress,
      recoveryManagerAddress,
      tokenDeployerAddress,
      govDeployerAddress,
      deployer.address, // initialOwner
    ],
    {
      initializer: "initialize",
      kind: "uups",
    },
  );
  await factory.waitForDeployment();
  const factoryAddress = await factory.getAddress();
  console.log("-> AssetFactory Proxy deployed to:", factoryAddress);

  // 7. Deploy RemzikMarketplace as a UUPS Proxy
  console.log("\n[6/7] Deploying RemzikMarketplace Proxy...");
  const Marketplace = await ethers.getContractFactory("RemzikMarketplace");
  const marketplace = await upgradesApi.deployProxy(
    Marketplace,
    [
      registryAddress,
      priceOracleAddress,
      deployer.address, // initialOwner passed to __Ownable_init
    ],
    {
      initializer: "initialize",
      kind: "uups",
    },
  );
  await marketplace.waitForDeployment();
  const marketplaceAddress = await marketplace.getAddress();
  console.log("-> RemzikMarketplace Proxy deployed to:", marketplaceAddress);

  // 8. Deploy Yield Notary
  console.log("\n[7/7] Deploying YieldNotary...");
  const YieldNotary = await ethers.getContractFactory("YieldNotary");
  const yieldNotary = await YieldNotary.deploy();
  await yieldNotary.waitForDeployment();
  const yieldNotaryAddress = await yieldNotary.getAddress();
  console.log("-> YieldNotary deployed to:", yieldNotaryAddress);

  // 9. Bind RecoveryManager inside the Identity Registry Proxy
  console.log("\n--- Post-Deployment Configuration ---");
  const tx = await registry.setRecoveryManager(recoveryManagerAddress);
  await tx.wait();
  console.log(
    "-> RecoveryManager bound to IdentityRegistry Proxy successfully!",
  );

  // --- SUMMARY ---
  console.log("\n=======================================");
  console.log("   DEPLOYED DEPLOYMENT SUMMARY FOR .ENV ");
  console.log("=======================================");
  console.log(`COMPLIANCE_CONTRACT_ADDRESS=${registryAddress}`);
  console.log(`ASSET_FACTORY_CONTRACT_ADDRESS=${factoryAddress}`);
  console.log(`TOKEN_DEPLOYER_ADDRESS=${tokenDeployerAddress}`);
  console.log(`GOV_DEPLOYER_ADDRESS=${govDeployerAddress}`);
  console.log(`MARKETPLACE_CONTRACT_ADDRESS=${marketplaceAddress}`);
  console.log(`YIELD_NOTARY_ADDRESS=${yieldNotaryAddress}`);
  console.log(`RECOVERY_MANAGER_CONTRACT_ADDRESS=${recoveryManagerAddress}`);
  console.log("=======================================\n");
}

main().catch((error) => {
  console.error("Deployment failed:", error);
  process.exitCode = 1;
});
