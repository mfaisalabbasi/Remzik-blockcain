import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("AllContracts", (m) => {
  // 1. Deploy the Identity Registry (The Gatekeeper)
  const registry = m.contract("RemzikIdentityRegistry", []);

  // 2. Deploy the Asset Factory (The Producer)
  const factory = m.contract("AssetFactory", [registry]);

  // 3. Deploy the Marketplace (The Executor)
  const marketplace = m.contract("RemzikMarketplace", [registry]);

  // 4. Deploy the Yield Notary (The Auditor)
  // This records the "fingerprint" of financial distributions
  const yieldNotary = m.contract("YieldNotary", []);

  // Return all four
  return { registry, factory, marketplace, yieldNotary };
});
