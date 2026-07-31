// ignition/modules/AllContracts.ts
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("AllContracts", (m) => {
  // Get the default deployer/admin account
  const deployer = m.getAccount(0);

  // 1. Deploy Identity Registry
  const registry = m.contract("RemzikIdentityRegistry", []);

  // 2. Deploy Price Oracle
  const priceOracle = m.contract("PriceOracle", []);

  // 3. Deploy Micro-Deployer Utility Contracts (Required for Asset Pod bytecode injection)
  const tokenDeployer = m.contract("TokenDeployer", []);
  const govDeployer = m.contract("GovDeployer", []);

  // 7. Deploy Recovery Manager (Phase 10: Linked to Identity Registry and Admin)
  const recoveryManager = m.contract("RecoveryManager", [registry, deployer]);

  // 4. Deploy Asset Factory (Linked to Registry, RecoveryManager, TokenDeployer, and GovDeployer)
  const factory = m.contract("AssetFactory", [
    registry,
    recoveryManager,
    tokenDeployer,
    govDeployer,
  ]);

  // 5. Deploy Marketplace (Linked to Registry and Oracle)
  const marketplace = m.contract("RemzikMarketplace", [registry, priceOracle]);

  // 6. Deploy Yield Notary
  const yieldNotary = m.contract("YieldNotary", []);

  // 8. Bind RecoveryManager to Identity Registry so it has authorization to update verification statuses atomically
  m.call(registry, "setRecoveryManager", [recoveryManager]);

  return {
    registry,
    priceOracle,
    tokenDeployer,
    govDeployer,
    factory,
    marketplace,
    yieldNotary,
    recoveryManager,
  };
});
