import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("AllContracts", (m) => {
  // 1. Deploy the Identity Registry (The Gatekeeper)
  const registry = m.contract("RemzikIdentityRegistry", []);

  // 2. Deploy the Asset Factory (The Producer)
  // Needs registry for verifying users during asset creation
  const factory = m.contract("AssetFactory", [registry]);

  // 3. Deploy the Marketplace (The Executor)
  // Needs registry to check if buyer/seller are verified before trading
  const marketplace = m.contract("RemzikMarketplace", [registry]);

  // Return all three
  return { registry, factory, marketplace };
});
