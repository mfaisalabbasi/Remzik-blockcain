// ignition/modules/AllContracts.ts
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("AllContracts", (m) => {
  // 1. Deploy Identity Registry
  const registry = m.contract("RemzikIdentityRegistry", []);

  // 2. Deploy Price Oracle
  const priceOracle = m.contract("PriceOracle", []);

  // 3. Deploy Micro-Deployer Utility Contracts (Required for Asset Pod bytecode injection)
  const tokenDeployer = m.contract("TokenDeployer", []);
  const govDeployer = m.contract("GovDeployer", []);

  // 4. Deploy Asset Factory (Linked to Registry, TokenDeployer, and GovDeployer)
  const factory = m.contract("AssetFactory", [
    registry,
    tokenDeployer,
    govDeployer,
  ]);

  // 5. Deploy Marketplace (Linked to Registry and Oracle)
  const marketplace = m.contract("RemzikMarketplace", [registry, priceOracle]);

  // 6. Deploy Yield Notary
  const yieldNotary = m.contract("YieldNotary", []);

  return {
    registry,
    priceOracle,
    tokenDeployer,
    govDeployer,
    factory,
    marketplace,
    yieldNotary,
  };
});
