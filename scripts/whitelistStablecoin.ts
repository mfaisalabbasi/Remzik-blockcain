import hre from "hardhat";

async function main() {
  const connection = await hre.network.create();
  const { ethers } = connection;

  // 1. Lowercase first, then let ethers compute the valid EIP-55 checksum
  const rawVaultAddress =
    "0x6f1216d1BFe15c98520CA1434FC1d9d57AC95321".toLowerCase();
  const treasuryVaultAddress = ethers.getAddress(rawVaultAddress);

  const mockUSDCAddress = ethers.getAddress(
    "0x5FbDB2315678afecb367f032d93F642f64180aa3".toLowerCase(),
  );

  const [deployer] = await ethers.getSigners();
  const vault = await ethers.getContractAt(
    "TreasuryVault",
    treasuryVaultAddress,
    deployer,
  );

  console.log(
    `Whitelisting MockUSDC (${mockUSDCAddress}) on Treasury Vault (${treasuryVaultAddress})...`,
  );

  const tx = await vault.setStablecoinStatus(mockUSDCAddress, true);
  await tx.wait();

  console.log("-> Successfully whitelisted stablecoin on the vault!");
}

main().catch((error) => {
  console.error("Whitelisting failed:", error);
  process.exitCode = 1;
});
