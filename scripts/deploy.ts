import hre from "hardhat";
import { upgrades } from "@openzeppelin/hardhat-upgrades";

async function main() {
  // 1. Establish network connection & create upgrades instance for Hardhat 3
  const connection = await hre.network.create();
  const { ethers } = connection;
  const upgradesApi = await upgrades(hre, connection);

  const [deployer] = await ethers.getSigners();
  console.log("Deploying Remzik contracts with account:", deployer.address);

  // 1.5 Deploy Mock USDC (The Stablecoin for testing)
  console.log("\n[0/8] Deploying MockUSDC...");
  const MockUSDC = await ethers.getContractFactory("MockUSDC");
  const mockUSDC = await MockUSDC.deploy();
  await mockUSDC.waitForDeployment();
  const mockUSDCAddress = await mockUSDC.getAddress();
  console.log("-> MockUSDC deployed to:", mockUSDCAddress);

  // Mint some initial MockUSDC to the deployer/test wallet
  const initialMint = ethers.parseUnits("100000", 6); // 100,000 USDC
  await mockUSDC.mint(deployer.address, initialMint);
  console.log("-> Minted 100,000 MockUSDC to deployer:", deployer.address);

  // 2. Deploy RemzikIdentityRegistry as a UUPS Proxy
  console.log("\n[1/8] Deploying RemzikIdentityRegistry Proxy...");
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
  console.log("\n[2/8] Deploying PriceOracle...");
  const PriceOracle = await ethers.getContractFactory("PriceOracle");
  const priceOracle = await PriceOracle.deploy();
  await priceOracle.waitForDeployment();
  const priceOracleAddress = await priceOracle.getAddress();
  console.log("-> PriceOracle deployed to:", priceOracleAddress);

  // 4. Deploy Micro-Deployer Utility Contracts
  console.log("\n[3/8] Deploying TokenDeployer & GovDeployer...");
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
  console.log("\n[4/8] Deploying RecoveryManager Proxy...");
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
  console.log("\n[5/8] Deploying AssetFactory Proxy...");
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
      deployer.address, // initialAdmin
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
  console.log("\n[6/8] Deploying RemzikMarketplace Proxy...");
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

  // 8. Deploy Engine 2 TreasuryVault (Implementation Logic Contract for Clones/Proxies)
  console.log("\n[7/8] Deploying TreasuryVault Implementation...");
  const TreasuryVault = await ethers.getContractFactory("TreasuryVault");
  const treasuryVault = await TreasuryVault.deploy();
  await treasuryVault.waitForDeployment();
  const treasuryVaultAddress = await treasuryVault.getAddress();
  console.log(
    "-> TreasuryVault Implementation deployed to:",
    treasuryVaultAddress,
  );

  // 9. Deploy Yield Notary
  console.log("\n[8/8] Deploying YieldNotary...");
  const YieldNotary = await ethers.getContractFactory("YieldNotary");
  const yieldNotary = await YieldNotary.deploy();
  await yieldNotary.waitForDeployment();
  const yieldNotaryAddress = await yieldNotary.getAddress();
  console.log("-> YieldNotary deployed to:", yieldNotaryAddress);

  // 10. Post-Deployment Configuration & RBAC Bindings
  console.log("\n--- Post-Deployment Configuration ---");

  // Ensure deployer explicitly holds required roles on Identity Registry before cross-calls
  const kycManagerRole = await registry.KYC_MANAGER_ROLE();
  const operatorRole = await registry.OPERATOR_ROLE();

  if (!(await registry.hasRole(kycManagerRole, deployer.address))) {
    let txRole = await registry.grantRole(kycManagerRole, deployer.address);
    await txRole.wait();
  }
  if (!(await registry.hasRole(operatorRole, deployer.address))) {
    let txRole = await registry.grantRole(operatorRole, deployer.address);
    await txRole.wait();
  }

  // Bind RecoveryManager inside Identity Registry
  let tx = await registry.setRecoveryManager(recoveryManagerAddress);
  await tx.wait();
  console.log(
    "-> RecoveryManager bound to IdentityRegistry Proxy successfully!",
  );

  // Bind TreasuryVault Implementation inside AssetFactory
  tx = await factory.setTreasuryVaultImplementation(treasuryVaultAddress);
  await tx.wait();
  console.log(
    "-> TreasuryVault implementation linked to AssetFactory successfully!",
  );

  // Configure default stablecoin inside AssetFactory for automatic whitelisting on new asset deployments
  tx = await factory.setDefaultStablecoin(mockUSDCAddress);
  await tx.wait();
  console.log(
    "-> Default MockUSDC registered in AssetFactory for auto-whitelisting!",
  );

  // Configure marketplace reference inside AssetFactory so new assets auto-whitelist marketplace for compliance bypass
  tx = await factory.setMarketplace(marketplaceAddress);
  await tx.wait();
  console.log(
    "-> RemzikMarketplace linked to AssetFactory for automated compliance bypass!",
  );

  // --- SUMMARY ---
  console.log("\n=======================================");
  console.log("   DEPLOYED DEPLOYMENT SUMMARY FOR .ENV ");
  console.log("=======================================");
  console.log(`NEXT_PUBLIC_STABLECOIN_ADDRESS=${mockUSDCAddress}`);
  console.log(`COMPLIANCE_CONTRACT_ADDRESS=${registryAddress}`);
  console.log(`ASSET_FACTORY_CONTRACT_ADDRESS=${factoryAddress}`);
  console.log(`TOKEN_DEPLOYER_ADDRESS=${tokenDeployerAddress}`);
  console.log(`GOV_DEPLOYER_ADDRESS=${govDeployerAddress}`);
  console.log(`MARKETPLACE_CONTRACT_ADDRESS=${marketplaceAddress}`);
  console.log(`YIELD_NOTARY_ADDRESS=${yieldNotaryAddress}`);
  console.log(`RECOVERY_MANAGER_CONTRACT_ADDRESS=${recoveryManagerAddress}`);
  console.log(`TREASURY_VAULT_IMPLEMENTATION_ADDRESS=${treasuryVaultAddress}`);
  console.log("=======================================\n");
}

main().catch((error) => {
  console.error("Deployment failed:", error);
  process.exitCode = 1;
});
