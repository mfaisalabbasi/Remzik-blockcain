import { expect } from "chai";
import { network } from "hardhat";

// Initialize a clean, isolated environment to ensure 100% deterministic test behavior
const { ethers } = await network.create();

describe("RemzikIdentityRegistry: Enterprise Compliance Ledger", function () {
  let registry: any;
  let owner: any;
  let complianceAdmin: any;
  let investor: any;
  let maliciousActor: any;

  before(async function () {
    // Acquire distinct operational signers
    const signers = await ethers.getSigners();
    [owner, complianceAdmin, investor, maliciousActor] = signers;
  });

  beforeEach(async function () {
    // Deploy contract in a fresh, isolated state
    registry = await ethers.deployContract("RemzikIdentityRegistry", [], owner);
    await registry.waitForDeployment();
  });

  describe("Initialization & Ownership", function () {
    it("Should correctly assign the deployer as the initial system owner", async function () {
      expect(await registry.owner()).to.equal(owner.address);
    });

    it("Should reject administrative transfers from non-owner accounts", async function () {
      await expect(
        registry
          .connect(maliciousActor)
          .transferOwnership(complianceAdmin.address),
      ).to.be.revertedWithCustomError(registry, "UnauthorizedCaller");
    });
  });

  describe("KYC Identity Lifecycle", function () {
    it("Should register an identity, update state, and emit IdentityUpdated event", async function () {
      await expect(
        registry.connect(owner).registerIdentity(investor.address, true),
      )
        .to.emit(registry, "IdentityUpdated")
        .withArgs(investor.address, true, owner.address);

      const [isVerified] = await registry.getIdentityState(investor.address);
      expect(isVerified).to.be.true;
    });

    it("Should revert when an unauthorized entity attempts to modify KYC status", async function () {
      await expect(
        registry
          .connect(maliciousActor)
          .registerIdentity(investor.address, true),
      ).to.be.revertedWithCustomError(registry, "UnauthorizedCaller");
    });
  });

  describe("Risk Mitigation & Asset Freeze Controls", function () {
    beforeEach(async function () {
      await registry.connect(owner).registerIdentity(investor.address, true);
    });

    it("Should prevent trading when an identity is explicitly frozen", async function () {
      await expect(registry.connect(owner).toggleFreeze(investor.address, true))
        .to.emit(registry, "IdentityFreezeToggled")
        .withArgs(investor.address, true, owner.address);

      // Gateway check should return false
      expect(await registry.isClearToTrade(investor.address)).to.be.false;
    });

    it("Should permit trading only after a frozen identity is restored", async function () {
      await registry.connect(owner).toggleFreeze(investor.address, true);
      await registry.connect(owner).toggleFreeze(investor.address, false);

      expect(await registry.isClearToTrade(investor.address)).to.be.true;
    });
  });

  describe("Gateway Security Logic", function () {
    it("Should verify that uninitialized users are blocked by default", async function () {
      expect(await registry.isClearToTrade(investor.address)).to.be.false;
    });

    it("Should confirm that verified and unfrozen users are clear to trade", async function () {
      await registry.connect(owner).registerIdentity(investor.address, true);
      expect(await registry.isClearToTrade(investor.address)).to.be.true;
    });
  });
});
