import hre from "hardhat";

async function main() {
  const connection = await hre.network.create();
  const { ethers } = connection;

  const [sender] = await ethers.getSigners();
  const target = "0xD43BFC1685BA3B49fDD560F51F116D44A2892dd2";

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
