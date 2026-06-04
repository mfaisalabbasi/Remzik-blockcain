import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("AllContracts", (m) => {
  // 1. Deploy the Registry first
  const registry = m.contract("Registry", []);

  // 2. Deploy the Factory, passing the registry address automatically
  const assetFactory = m.contract("AssetFactory", [registry]);

  return { registry, assetFactory };
});
