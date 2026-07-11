// ignition/modules/AllContracts.ts
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("AllContracts", (m) => {
  // 1. Deploy Registry
  const registry = m.contract("RemzikIdentityRegistry", []);

  // 2. Deploy Price Oracle (The new Guardrail)
  const priceOracle = m.contract("PriceOracle", []);

  // 3. Deploy Asset Factory
  const factory = m.contract("AssetFactory", [registry]);

  // 4. Deploy Marketplace (Now linked to Registry AND Oracle)
  const marketplace = m.contract("RemzikMarketplace", [registry, priceOracle]);

  // 5. Deploy Yield Notary
  const yieldNotary = m.contract("YieldNotary", []);

  return { registry, priceOracle, factory, marketplace, yieldNotary };
});
