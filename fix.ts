import { ethers, network } from "hardhat";

async function main() {
  const [signer] = await ethers.getSigners();
  const registry = await ethers.getContractAt("RemzikIdentityRegistry", "0x5FbDB2315678afecb367f032d93F642f64180aa3");
  
  console.log("Network:", network.name);
  console.log("Verifying Admin Address:", signer.address);

  const tx = await registry.registerIdentity(signer.address, true);
  await tx.wait();
  
  console.log("SUCCESS: Identity Verified");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
