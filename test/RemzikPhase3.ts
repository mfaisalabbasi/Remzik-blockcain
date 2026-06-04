import { expect } from "chai";
import { network } from "hardhat";

const { ethers } = await network.create();

describe("Phase 3: Compliance-Exempt Treasury Operations", function () {
  let factory: any;
  let registry: any;
  let owner: any;
  let treasury: any;
  let investor: any;

  before(async function () {
    [owner, treasury, investor] = await ethers.getSigners();
  });

  beforeEach(async function () {
    registry = await ethers.deployContract("RemzikIdentityRegistry", [], owner);
    await registry.waitForDeployment();
    factory = await ethers.deployContract(
      "AssetFactory",
      [await registry.getAddress()],
      owner,
    );
    await factory.waitForDeployment();
  });

  it("Should allow Treasury to transfer without being in the Registry", async function () {
    const tx = await factory.deployAsset(
      "Tower",
      "TWR",
      1000,
      "meta",
      treasury.address,
    );
    const receipt = await tx.wait();

    // Get token instance
    const event = receipt?.logs.find(
      (l: any) =>
        l.topics[0] ===
        factory.interface.getEvent("AssetTokenDeployed").topicHash,
    );
    const decoded = factory.interface.parseLog({
      topics: event!.topics as string[],
      data: event!.data,
    });
    const token = await ethers.getContractAt(
      "RemzikAssetToken",
      decoded!.args[0],
    );

    // Note: Treasury is NOT registered. Investor is NOT registered.
    // Transfer from Treasury (Bypass) to Investor (Blocked) should fail.
    await expect(
      token.connect(treasury).transfer(investor.address, 100),
    ).to.be.revertedWith("ComplianceFailed: Receiver");
  });
});
