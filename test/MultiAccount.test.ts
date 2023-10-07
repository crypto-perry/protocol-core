import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

function getFunctionSelector(functionSignature: string): string {
  const hash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(functionSignature));
  return hash.slice(0, 10);  // The function selector is the first 4 bytes of the hash.
}

describe("MultiAccount", function() {
  let multiAccount: any;
  let admin: SignerWithAddress, addr1: SignerWithAddress, addr2: SignerWithAddress;

  beforeEach(async function() {
    [admin, addr1, addr2] = await ethers.getSigners();

    const SymmioParty = await ethers.getContractFactory("MockSymmioParty");

    const Factory = await ethers.getContractFactory("MultiAccount");
    const MultiAccount = await upgrades.deployProxy(Factory, [
      await admin.getAddress(), await addr1.getAddress(),
    ], { initializer: "initialize" });
    multiAccount = await MultiAccount.deployed();

    await multiAccount.connect(admin).setPartyImplementation(SymmioParty.bytecode);
  });

  describe("Initialization and Settings", function() {
    it("Should set the correct admin and Symmio address", async function() {
      expect(await multiAccount.hasRole(await multiAccount.DEFAULT_ADMIN_ROLE(), await admin.getAddress())).to.equal(true);
      expect(await multiAccount.hasRole(await multiAccount.PAUSER_ROLE(), await admin.getAddress())).to.equal(true);
      expect(await multiAccount.hasRole(await multiAccount.UNPAUSER_ROLE(), await admin.getAddress())).to.equal(true);
      expect(await multiAccount.hasRole(await multiAccount.SETTER_ROLE(), await admin.getAddress())).to.equal(true);
      expect(await multiAccount.hasRole(await multiAccount.PARTY_B_MANAGER_ROLE(), await admin.getAddress())).to.equal(true);
      expect(await multiAccount.symmioAddress()).to.equal(await addr1.getAddress());
    });

    it("should allow adding pair ops selector", async () => {
      const selector = getFunctionSelector("testFunction(bytes32)");
      const quoteIdIndex = 5;
      await multiAccount.addPairOpsSelector(selector, quoteIdIndex);

      expect(await multiAccount.pairOpsSelectors(selector)).to.equal(quoteIdIndex);
    });
  });

  describe("Role-based Access Control", function() {
    it("Should grant and revoke roles correctly", async function() {
      // Granting SETTER_ROLE to addr1
      await multiAccount.grantRole(await multiAccount.SETTER_ROLE(), await addr1.getAddress());
      expect(await multiAccount.hasRole(await multiAccount.SETTER_ROLE(), await addr1.getAddress())).to.equal(true);

      // Revoking SETTER_ROLE from addr1
      await multiAccount.revokeRole(await multiAccount.SETTER_ROLE(), await addr1.getAddress(), { from: await admin.getAddress() });
      expect(await multiAccount.hasRole(await multiAccount.SETTER_ROLE(), await addr1.getAddress())).to.equal(false);
    });

    it("Should not allow unauthorized access", async function() {
      // Trying to call a protected function from an unauthorized address
      await expect(multiAccount.connect(addr2).setPartyImplementation("0x00")).to.be.reverted;

      // Granting SETTER_ROLE to addr2 and trying again
      await multiAccount.grantRole(await multiAccount.SETTER_ROLE(), await addr2.getAddress());
      await expect(multiAccount.connect(addr2).setPartyImplementation("0x00")).to.not.be.reverted;
    });
  });

  describe("Account Management", function() {
    describe("PartyA", function() {
      it("Should create account", async function() {
        expect(await multiAccount.getAccountsLength(await addr2.getAddress())).to.be.equal(0);
        await multiAccount.connect(addr2).createPartyAAccount("Test");
        expect(await multiAccount.getAccountsLength(await addr2.getAddress())).to.be.equal(1);
        let createdAccount = (await multiAccount.getAccounts(await addr2.getAddress(), 0, 10))[0];
        expect(createdAccount.name).to.be.equal("Test");
        expect(await multiAccount.partyAOwners(createdAccount.accountAddress)).to.be.equal(await addr2.getAddress());
      });

      it("Should edit account name", async function() {
        await expect(multiAccount.connect(addr2).createPartyAAccount("Test")).to.not.be.reverted;
        let createdAccount = (await multiAccount.getAccounts(await addr2.getAddress(), 0, 10))[0];
        await expect(multiAccount.connect(addr1).editPartyAAccountName(createdAccount.accountAddress, "Renamed")).to.be.reverted;
        await multiAccount.connect(addr2).editPartyAAccountName(createdAccount.accountAddress, "Renamed");
        let renamedAccount = (await multiAccount.getAccounts(await addr2.getAddress(), 0, 10))[0];
        expect(renamedAccount.name).to.be.equal("Renamed");
      });

    });

    describe("PartyB", function() {
      it("Should check partyB manager role permission", async function() {
        await expect(multiAccount.connect(addr2).createPartyBAccount([])).to.be.reverted;
        await expect(multiAccount.connect(admin).createPartyBAccount([])).to.not.be.reverted;
      });

      it("Should create account", async function() {
        let tx = await multiAccount.connect(admin).createPartyBAccount([await addr1.getAddress()]);
        let createdAccount = (await tx.wait()).events?.filter((x: any) => x.event == "CreatePartyBAccount")[0]!.args!.account;
        expect(await multiAccount.partyBTrustedAddresses(createdAccount, 0)).to.be.equal(await addr1.getAddress());
      });

      describe("Should Add/Remove trustedAddresses", function() {
        let account: any;
        beforeEach(async function() {
          let tx = await multiAccount.connect(admin).createPartyBAccount([await addr1.getAddress()]);
          account = (await tx.wait()).events?.filter((x: any) => x.event == "CreatePartyBAccount")[0]!.args!.account;
        });

        it("Should add trusted address", async function() {
          await expect(multiAccount.connect(addr2).addTrustedAddressToPartyBAccount(account, [await addr2.getAddress()])).to.be.reverted;
          await (multiAccount.connect(admin).addTrustedAddressToPartyBAccount(account, [await addr2.getAddress()]));
          expect(await multiAccount.partyBTrustedAddresses(account, 0)).to.be.equal(await addr1.getAddress());
          expect(await multiAccount.partyBTrustedAddresses(account, 1)).to.be.equal(await addr2.getAddress());
        });

        it("Should remove trusted address", async function() {
          await expect(multiAccount.connect(addr2).removeTrustedAddressFromPartyBAccount(account, await addr1.getAddress())).to.be.reverted;
          await expect(multiAccount.connect(admin).removeTrustedAddressFromPartyBAccount(account, await addr2.getAddress()))
            .to.be.revertedWith("MultiAccount: Trusted address not found!");
          await (multiAccount.connect(admin).removeTrustedAddressFromPartyBAccount(account, await addr1.getAddress()));
        });
      });
    });
  });

  describe("Balance Management", function() {

  });

  describe("Method calling", function() {
    let partAAccount: any;
    let partBAccount: any;

    beforeEach(async function() {
      await multiAccount.connect(addr1).createPartyAAccount("Test");
      partAAccount = (await multiAccount.getAccounts(await addr1.getAddress(), 0, 10))[0].accountAddress;
      let tx = await multiAccount.connect(admin).createPartyBAccount([await addr1.getAddress()]);
      partBAccount = (await tx.wait()).events?.filter((x: any) => x.event == "CreatePartyBAccount")[0]!.args!.account;
    });

    it("should prevent unauthorized calls", async function() {
      const callData = ethers.utils.defaultAbiCoder.encode(
        ["bytes4", "uint256"],
        [ethers.utils.id("mockFunction(uint256)").slice(0, 10), 123],
      );
      await expect(multiAccount.connect(addr2).partyACall(partAAccount, [callData])).to.be.reverted;
      await expect(multiAccount.connect(addr2).partyBCall(partBAccount, [callData])).to.be.reverted;

      await expect(multiAccount.connect(addr1).partyACall(partAAccount, [callData])).to.not.be.reverted;
      await expect(multiAccount.connect(addr1).partyBCall(partBAccount, [callData])).to.not.be.reverted;
    });

  });

});

