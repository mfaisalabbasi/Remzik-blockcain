import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("AllContracts", (m) => {
  // 1. Deploy the real production registry
  const registry = m.contract("RemzikIdentityRegistry", []);

  // 2. Deploy the factory, passing the registry address
  const factory = m.contract("AssetFactory", [registry]);

  // Return them so Ignition knows they are the only two to track
  return { registry, factory };
});
