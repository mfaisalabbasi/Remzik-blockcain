import hre from "hardhat";

async function main() {
  // 1. Establish network connection for Hardhat 3
  const connection = await hre.network.create();
  const { ethers } = connection;

  // 2. Target investor wallet address
  const investorWalletAddress = "0xCF0f3cED44534052c85fDdf2E4e38A62b21F69A9";

  // 3. The MockUSDC contract address from your deployment
  const mockUSDCAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3";

  // 4. Amount to fund (e.g., 50,000 USDC)
  const amountToFund = "50000";

  console.log(`Funding wallet: ${investorWalletAddress}`);
  console.log(`Using MockUSDC contract: ${mockUSDCAddress}`);

  // Get the deployer signer
  const [deployer] = await ethers.getSigners();

  // Attach to the deployed MockUSDC contract
  const mockUSDC = await ethers.getContractAt(
    "MockUSDC",
    mockUSDCAddress,
    deployer,
  );

  // Parse amount using 6 decimals (USDC standard)
  const parsedAmount = ethers.parseUnits(amountToFund, 6);

  // Call the mint function
  const tx = await mockUSDC.mint(investorWalletAddress, parsedAmount);
  await tx.wait();

  // Check new balance
  const balance = await mockUSDC.balanceOf(investorWalletAddress);

  console.log("---------------------------------------------------");
  console.log(`Successfully minted ${amountToFund} MockUSDC!`);
  console.log(`New Wallet Balance: ${ethers.formatUnits(balance, 6)} USDC`);
  console.log("---------------------------------------------------");
}

main().catch((error) => {
  console.error("Funding failed:", error);
  process.exitCode = 1;
});
