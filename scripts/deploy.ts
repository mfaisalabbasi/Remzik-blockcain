import hre from "hardhat";
import { upgrades } from "@openzeppelin/hardhat-upgrades";

async function main() {
  // 1. Establish network connection & create upgrades instance
  const connection = await hre.network.create();
  const { ethers } = connection;
  const upgradesApi = await upgrades(hre, connection);

  const [deployer] = await ethers.getSigners();
  console.log("Deploying Remzik contracts with account:", deployer.address);

  try {
    // 1.5 Deploy Mock USDC (The Stablecoin for testing)
    console.log("\n[0/8] Deploying MockUSDC...");
    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    const mockUSDC = await MockUSDC.deploy();
    await mockUSDC.waitForDeployment();
    const mockUSDCAddress = await mockUSDC.getAddress();
    console.log("-> MockUSDC deployed to:", mockUSDCAddress);

    // Mint some initial MockUSDC to the deployer/test wallet
    const initialMint = ethers.parseUnits("100000", 6); // 100,000 USDC
    let tx = await mockUSDC.mint(deployer.address, initialMint);
    await tx.wait();
    console.log("-> Minted 100,000 MockUSDC to deployer:", deployer.address);

    // 2. Deploy RemzikIdentityRegistry as a UUPS Proxy
    console.log("\n[1/8] Deploying RemzikIdentityRegistry Proxy...");
    const IdentityRegistry = await ethers.getContractFactory(
      "RemzikIdentityRegistry",
    );
    const registry = await upgradesApi.deployProxy(IdentityRegistry, [], {
      initializer: "initialize",
      kind: "uups",
    });
    await registry.waitForDeployment();
    const registryAddress = await registry.getAddress();
    console.log(
      "-> RemzikIdentityRegistry Proxy deployed to:",
      registryAddress,
    );

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
      [registryAddress, deployer.address],
      {
        initializer: "initialize",
        kind: "uups",
      },
    );
    await recoveryManager.waitForDeployment();
    const recoveryManagerAddress = await recoveryManager.getAddress();
    console.log(
      "-> RecoveryManager Proxy deployed to:",
      recoveryManagerAddress,
    );

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
        deployer.address,
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
      [registryAddress, priceOracleAddress, deployer.address],
      {
        initializer: "initialize",
        kind: "uups",
      },
    );
    await marketplace.waitForDeployment();
    const marketplaceAddress = await marketplace.getAddress();
    console.log("-> RemzikMarketplace Proxy deployed to:", marketplaceAddress);

    // 🛡️ Whitelist MockUSDC as an accepted payment token in the Marketplace
    tx = await marketplace.setPaymentTokenStatus(mockUSDCAddress, true);
    await tx.wait();
    console.log(
      "-> MockUSDC whitelisted as an accepted payment token in RemzikMarketplace!",
    );

    // 🛡️ Whitelist RemzikMarketplace address in IdentityRegistry so escrow transfers pass compliance checks
    tx = await registry.setVerificationStatus(marketplaceAddress, true);
    await tx.wait();
    console.log(
      "-> RemzikMarketplace successfully verified in IdentityRegistry!",
    );

    // 8. Deploy Engine 2 TreasuryVault (Implementation Logic Contract)
    console.log("\n[7/8] Deploying TreasuryVault Implementation...");
    const TreasuryVault = await ethers.getContractFactory("TreasuryVault");
    const treasuryVault = await TreasuryVault.deploy();
    await treasuryVault.waitForDeployment();
    const treasuryVaultAddress = await treasuryVault.getAddress();
    console.log(
      "-> TreasuryVault Implementation deployed to:",
      treasuryVaultAddress,
    );

    // 9. Deploy Yield Notary (updated constructor arguments: initialOwner, stablecoin)
    console.log("\n[8/8] Deploying YieldNotary...");
    const YieldNotary = await ethers.getContractFactory("YieldNotary");
    const yieldNotary = await YieldNotary.deploy(
      deployer.address,
      mockUSDCAddress,
    );
    await yieldNotary.waitForDeployment();
    const yieldNotaryAddress = await yieldNotary.getAddress();
    console.log("-> YieldNotary deployed to:", yieldNotaryAddress);

    // 10. Post-Deployment Configuration & RBAC Bindings
    console.log("\n--- Post-Deployment Configuration ---");

    // Compute role hashes directly to bypass TypeScript artifact typing mismatches
    const kycManagerRole = ethers.keccak256(
      ethers.toUtf8Bytes("KYC_MANAGER_ROLE"),
    );
    const operatorRole = ethers.keccak256(ethers.toUtf8Bytes("OPERATOR_ROLE"));
    const assetFactoryRole = ethers.keccak256(
      ethers.toUtf8Bytes("ASSET_FACTORY_ROLE"),
    );
    const assetDeployerRole = ethers.keccak256(
      ethers.toUtf8Bytes("ASSET_DEPLOYER_ROLE"),
    );

    if (!(await registry.hasRole(kycManagerRole, deployer.address))) {
      const txRole1 = await registry.grantRole(
        kycManagerRole,
        deployer.address,
      );
      await txRole1.wait();
    }
    if (!(await registry.hasRole(operatorRole, deployer.address))) {
      const txRole2 = await registry.grantRole(operatorRole, deployer.address);
      await txRole2.wait();
    }

    // Grant ASSET_FACTORY_ROLE to AssetFactory Proxy
    if (!(await registry.hasRole(assetFactoryRole, factoryAddress))) {
      const txRole3 = await registry.grantRole(
        assetFactoryRole,
        factoryAddress,
      );
      await txRole3.wait();
      console.log(
        "-> ASSET_FACTORY_ROLE granted to AssetFactory Proxy on IdentityRegistry!",
      );
    }

    // Grant ASSET_DEPLOYER_ROLE to deployer on AssetFactory Proxy
    if (!(await factory.hasRole(assetDeployerRole, deployer.address))) {
      const txRole4 = await factory.grantRole(
        assetDeployerRole,
        deployer.address,
      );
      await txRole4.wait();
      console.log(
        "-> ASSET_DEPLOYER_ROLE successfully forced and granted to deployer on AssetFactory!",
      );
    }

    // Bind RecoveryManager inside Identity Registry
    tx = await registry.setRecoveryManager(recoveryManagerAddress);
    await tx.wait();
    console.log(
      "-> RecoveryManager bound to IdentityRegistry Proxy successfully!",
    );

    // Link TokenDeployer & GovDeployer implementations to AssetFactory Proxy
    tx = await factory.setDeployers(tokenDeployerAddress, govDeployerAddress);
    await tx.wait();
    console.log(
      "-> TokenDeployer & GovDeployer linked to AssetFactory successfully!",
    );

    // Bind TreasuryVault Implementation inside AssetFactory
    tx = await factory.setTreasuryVaultImplementation(treasuryVaultAddress);
    await tx.wait();
    console.log(
      "-> TreasuryVault implementation linked to AssetFactory successfully!",
    );

    // Configure default stablecoin inside AssetFactory
    tx = await factory.setDefaultStablecoin(mockUSDCAddress);
    await tx.wait();
    console.log(
      "-> Default MockUSDC registered in AssetFactory for auto-whitelisting!",
    );

    // Configure marketplace reference inside AssetFactory
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
    console.log(
      `TREASURY_VAULT_IMPLEMENTATION_ADDRESS=${treasuryVaultAddress}`,
    );
    console.log("=======================================\n");
  } catch (error: any) {
    console.error("\n❌ Deployment failed with error details:");
    console.error("Message:", error.message);
    if (error.data) console.error("Data:", error.data);
    if (error.shortMessage) console.error("Short Message:", error.shortMessage);
    throw error;
  }
}

main().catch((error) => {
  process.exitCode = 1;
});
