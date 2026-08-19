import hre from "hardhat";

async function main() {
  const connection = await hre.network.create();
  const { ethers } = connection;

  const [sender] = await ethers.getSigners();
  const target = "0x7f633d78f97D320c65D37739d6215988C007d5c0";

  console.log(`Funding ${target} from ${sender.address}...`);

  // 1. Send the transaction
  const tx = await sender.sendTransaction({
    to: target,
    value: ethers.parseEther("100.0"),
  });
  await tx.wait();
  console.log("Success! Transaction Hash:", tx.hash);

  // 2. Immediately check balance on the SAME connection
  const balance = await ethers.provider.getBalance(target);
  console.log(
    `Current Balance of ${target}: ${ethers.formatEther(balance)} ETH`,
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
