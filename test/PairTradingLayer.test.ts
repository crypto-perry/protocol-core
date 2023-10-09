import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { initializeFixture } from "./Initialize.fixture";
import { User } from "./models/User";
import { decimal } from "./utils/Common";
import { Hedger } from "./models/Hedger";
import { RunContext } from "./models/RunContext";
import { Contract, ContractFactory } from "ethers";
import { limitQuoteRequestBuilder, QuoteRequest } from "./models/requestModels/QuoteRequest";
import { PositionType } from "./models/Enums";
import { getDummySingleUpnlSig } from "./utils/SignatureUtils";

function getFunctionAbi(contract: Contract | ContractFactory, functionName: string) {
  for (const abi of Object.keys(contract.interface.functions))
    if (abi.startsWith(functionName + "("))
      return abi;
  throw Error("Function not found: " + functionName);
}

function getFunctionSelector(contract: Contract | ContractFactory, functionName: string) {
  return ethers.utils.keccak256(ethers.utils.toUtf8Bytes(getFunctionAbi(contract, functionName))).slice(0, 10);
}


async function getListFormat(request: QuoteRequest): Promise<any> {
  return [
    request.partyBWhiteList,
    request.symbolId,
    request.positionType,
    request.orderType,
    request.price,
    request.quantity,
    request.cva,
    request.lf,
    request.partyAmm,
    request.partyBmm,
    request.maxFundingRate,
    await request.deadline,
    await request.upnlSig,
  ];
}

export function shouldBehaveLikePairTradingLayer() {
  let layer: any;
  let context: RunContext;
  let user: User;
  let hedger: Hedger;
  let symmioAddress: any;

  beforeEach(async function() {
    context = await loadFixture(initializeFixture);
    symmioAddress = context.diamond;

    user = new User(context, context.signers.user);
    await user.setup();
    await user.setBalances(decimal(2000), decimal(1000), decimal(500));

    hedger = new Hedger(context, context.signers.hedger);
    await hedger.setup();
    await hedger.setBalances(decimal(2000), decimal(1000));

    const SymmioParty = await ethers.getContractFactory("SymmioParty");

    const Factory = await ethers.getContractFactory("PairTradingLayer");
    const Layer = await upgrades.deployProxy(Factory, [
      await context.signers.admin.getAddress(), symmioAddress,
    ], { initializer: "initialize" });
    layer = await Layer.deployed();

    await layer.connect(context.signers.admin).setPartyImplementation(SymmioParty.bytecode);
  });

  describe("Initialization and Settings", function() {
    it("Should set the correct admin and Symmio address", async function() {
      const adminAddress = await context.signers.admin.getAddress();
      expect(await layer.hasRole(await layer.DEFAULT_ADMIN_ROLE(), adminAddress)).to.equal(true);
      expect(await layer.hasRole(await layer.PAUSER_ROLE(), adminAddress)).to.equal(true);
      expect(await layer.hasRole(await layer.UNPAUSER_ROLE(), adminAddress)).to.equal(true);
      expect(await layer.hasRole(await layer.SETTER_ROLE(), adminAddress)).to.equal(true);
      expect(await layer.symmioAddress()).to.equal(symmioAddress);
    });

    it("should allow adding pair ops selector", async () => {
      const selector = getFunctionSelector(context.partyAFacet, "sendQuote");
      const quoteIdIndex = 5;
      await layer.addPairOpsSelector(selector, quoteIdIndex);
      expect(await layer.pairOpsSelectors(selector)).to.equal(quoteIdIndex);
    });
  });

  describe("Role-based Access Control", function() {
    it("Should grant and revoke roles correctly", async function() {

      const userAddress = await context.signers.user.getAddress();
      const adminAddress = await context.signers.admin.getAddress();

      // Granting SETTER_ROLE to addr1
      await layer.grantRole(await layer.SETTER_ROLE(), userAddress);
      expect(await layer.hasRole(await layer.SETTER_ROLE(), userAddress)).to.equal(true);

      // Revoking SETTER_ROLE from addr1
      await layer.revokeRole(await layer.SETTER_ROLE(), userAddress, { from: adminAddress });
      expect(await layer.hasRole(await layer.SETTER_ROLE(), userAddress)).to.equal(false);
    });

    it("Should not allow unauthorized access", async function() {
      // Trying to call a protected function from an unauthorized address
      await expect(layer.connect(context.signers.user).setPartyImplementation("0x00")).to.be.reverted;

      // Granting SETTER_ROLE to addr2 and trying again
      await layer.grantRole(await layer.SETTER_ROLE(), await context.signers.user.getAddress());
      await expect(layer.connect(context.signers.user).setPartyImplementation("0x00")).to.not.be.reverted;
    });
  });

  describe("Account Management", function() {
    describe("PartyA", function() {
      it("Should create account", async function() {
        const userAddress = await context.signers.user.getAddress();

        expect(await layer.getAccountsLength(userAddress)).to.be.equal(0);

        await layer.connect(context.signers.user).createPartyAAccount("Test");

        expect(await layer.getAccountsLength(userAddress)).to.be.equal(1);
        let createdAccount = (await layer.getAccounts(userAddress, 0, 10))[0];
        expect(createdAccount.name).to.be.equal("Test");
        expect(await layer.partyAOwners(createdAccount.accountAddress)).to.be.equal(userAddress);
      });

      it("Should edit account name", async function() {
        const userAddress = await context.signers.user.getAddress();
        await expect(layer.connect(context.signers.user).createPartyAAccount("Test")).to.not.be.reverted;

        let createdAccount = (await layer.getAccounts(userAddress, 0, 10))[0];
        await expect(layer.connect(context.signers.user2).editPartyAAccountName(createdAccount.accountAddress, "Renamed")).to.be.reverted;
        await layer.connect(context.signers.user).editPartyAAccountName(createdAccount.accountAddress, "Renamed");
        let renamedAccount = (await layer.getAccounts(userAddress, 0, 10))[0];
        expect(renamedAccount.name).to.be.equal("Renamed");
      });

    });

    describe("PartyB", function() {

      it("Should create account", async function() {
        const userAddress = await context.signers.user.getAddress();
        const adminAddress = await context.signers.admin.getAddress();

        let tx = await layer.connect(context.signers.admin).createPartyBAccount([userAddress]);
        let account = (await tx.wait()).events?.filter((x: any) => x.event == "CreatePartyBAccount")[0]!.args!.account;

        expect(await layer.partyBTrustedAddress(account, adminAddress)).to.be.equal(false);
        expect(await layer.partyBTrustedAddress(account, userAddress)).to.be.equal(true);

        expect(await layer.partyBAdminAddress(account, adminAddress)).to.be.equal(true);
        expect(await layer.partyBAdminAddress(account, userAddress)).to.be.equal(false);
      });

      describe("Should Add/Remove trustedAddresses", function() {
        let account: any;
        beforeEach(async function() {
          const userAddress = await context.signers.user.getAddress();
          let tx = await layer.connect(context.signers.admin).createPartyBAccount([userAddress]);
          account = (await tx.wait()).events?.filter((x: any) => x.event == "CreatePartyBAccount")[0]!.args!.account;
        });

        it("Should add trusted address", async function() {
          const userAddress = await context.signers.user.getAddress();
          const user2Address = await context.signers.user2.getAddress();

          // Should revert on invalid admin
          await expect(layer.connect(context.signers.user2)
            .addTrustedAddressToPartyBAccount(account, [user2Address])).to.be.reverted;

          await (layer.connect(context.signers.admin).addTrustedAddressToPartyBAccount(account, [user2Address]));
          expect(await layer.partyBTrustedAddress(account, userAddress)).to.be.equal(true);
          expect(await layer.partyBTrustedAddress(account, user2Address)).to.be.equal(true);
        });

        it("Should remove trusted address", async function() {
          const userAddress = await context.signers.user.getAddress();

          // Should revert on invalid admin
          await expect(layer.connect(context.signers.user2).removeTrustedAddressFromPartyBAccount(account, [userAddress])).to.be.reverted;

          await (layer.connect(context.signers.admin).removeTrustedAddressFromPartyBAccount(account, [userAddress]));
          expect(await layer.partyBTrustedAddress(account, userAddress)).to.be.equal(false);
        });
      });
    });
  });

  describe("Balance Management", function() {
    let partyAAccount: any;
    let partyBAccount: any;

    beforeEach(async function() {
      const userAddress = await context.signers.user.getAddress();

      await layer.connect(context.signers.user).createPartyAAccount("Test");
      partyAAccount = (await layer.getAccounts(userAddress, 0, 10))[0].accountAddress;

      let tx = await layer.connect(context.signers.admin).createPartyBAccount([userAddress]);
      partyBAccount = (await tx.wait()).events?.filter((x: any) => x.event == "CreatePartyBAccount")[0]!.args!.account;

      await context.collateral
        .connect(context.signers.user)
        .approve(layer.address, ethers.constants.MaxUint256);
    });

    it("Should deposit for account", async () => {
      //partyA
      await layer.connect(context.signers.user).depositForAccount(partyAAccount, decimal(100));
      expect(await context.viewFacet.balanceOf(partyAAccount)).to.be.equal(decimal(100));

      //partyB
      await layer.connect(context.signers.user).depositForAccount(partyBAccount, decimal(105));
      expect(await context.viewFacet.balanceOf(partyBAccount)).to.be.equal(decimal(105));
    });

    it("Should deposit and allocate for account partyA", async () => {
      await layer.connect(context.signers.user).depositAndAllocateForPartyAAccount(partyAAccount, decimal(100));
      expect((await context.viewFacet.balanceInfoOfPartyA(partyAAccount))[0]).to.be.equal(decimal(100));
    });

    it("Should withdraw from account", async () => {
      //partyA
      await layer.connect(context.signers.user).depositForAccount(partyAAccount, decimal(100));
      expect(await context.viewFacet.balanceOf(partyAAccount)).to.be.equal(decimal(100));
      await layer.connect(context.signers.user).withdrawFromAccountPartyA(partyAAccount, decimal(50));
      expect(await context.viewFacet.balanceOf(partyAAccount)).to.be.equal(decimal(50));

      //partyB
      await layer.connect(context.signers.user).depositForAccount(partyBAccount, decimal(105));
      expect(await context.viewFacet.balanceOf(partyBAccount)).to.be.equal(decimal(105));
      await layer.connect(context.signers.admin)
        .withdrawFromAccountPartyB(partyBAccount, decimal(50), await context.signers.user.getAddress());
      expect(await context.viewFacet.balanceOf(partyBAccount)).to.be.equal(decimal(55));
    });
  });

  describe("Method calling", function() {
    let partyAAccount: any;
    let partyBAccount: any;

    beforeEach(async function() {
      const userAddress = await context.signers.user.getAddress();

      await layer.connect(context.signers.user).createPartyAAccount("Test");
      partyAAccount = (await layer.getAccounts(userAddress, 0, 10))[0].accountAddress;

      let tx = await layer.connect(context.signers.admin).createPartyBAccount([userAddress]);
      partyBAccount = (await tx.wait()).events?.filter((x: any) => x.event == "CreatePartyBAccount")[0]!.args!.account;
      await context.controlFacet.connect(context.signers.admin).registerPartyB(partyBAccount);

      await context.collateral
        .connect(context.signers.user)
        .approve(layer.address, ethers.constants.MaxUint256);

      await layer.connect(context.signers.user).depositAndAllocateForPartyAAccount(partyAAccount, decimal(500));
      await layer.connect(context.signers.user).depositForAccount(partyBAccount, decimal(500));
    });

    it("should prevent unauthorized calls", async function() {
      const callData = ethers.utils.defaultAbiCoder.encode(
        ["bytes4", "uint256"],
        [ethers.utils.id("mockFunction(uint256)").slice(0, 10), 123],
      );
      await expect(layer.connect(context.signers.user2).partyACall(partyAAccount, [callData])).to.be.reverted;
      await expect(layer.connect(context.signers.user2).partyBCall(partyBAccount, [callData])).to.be.reverted;
    });

    it("should set sendQuoteSelector", async () => {
      const sendQuoteSelector = getFunctionSelector(context.partyAFacet, "sendQuote");
      await layer.connect(context.signers.admin).setSendQuoteSelector(sendQuoteSelector);
      expect(await layer.sendQuoteSelector()).to.be.equal(sendQuoteSelector);
    });

    it("should add pairOpsSelectors", async () => {
      const selector = getFunctionSelector(context.partyAFacet, "requestToClosePosition");
      await layer.connect(context.signers.admin).addPairOpsSelector(selector, 4);
      expect(await layer.pairOpsSelectors(selector)).to.be.equal(4);
    });

    describe("Should work with paired quotes", function() {
      beforeEach(async () => {
        const sendQuoteSelector = getFunctionSelector(context.partyAFacet, "sendQuote");
        await layer.connect(context.signers.admin).setSendQuoteSelector(sendQuoteSelector);

        const requestToCloseSelector = getFunctionSelector(context.partyAFacet, "requestToClosePosition");
        await layer.connect(context.signers.admin).addPairOpsSelector(requestToCloseSelector, 4);

        const lockQuoteSelector = getFunctionSelector(context.partyBFacet, "lockQuote");
        await layer.connect(context.signers.admin).addPairOpsSelector(lockQuoteSelector, 4);

        const openPositionSelector = getFunctionSelector(context.partyBFacet, "openPosition");
        await layer.connect(context.signers.admin).addPairOpsSelector(openPositionSelector, 4);

        const fillCloseSelector = getFunctionSelector(context.partyBFacet, "fillCloseRequest");
        await layer.connect(context.signers.admin).addPairOpsSelector(fillCloseSelector, 4);
      });

      it("Should call single sendQuotes", async () => {
        let quoteRequest1 = limitQuoteRequestBuilder().build();
        let sendQuote1 = context.partyAFacet.interface.encodeFunctionData("sendQuote",
          await getListFormat(quoteRequest1));
        await layer.connect(context.signers.user).partyACall(partyAAccount, [sendQuote1]);
      });

      it("Should prevent more than two quotes", async () => {
        let request = limitQuoteRequestBuilder().build();
        let callData = context.partyAFacet.interface.encodeFunctionData("sendQuote",
          await getListFormat(request));
        await expect(layer.connect(context.signers.user).partyACall(partyAAccount, [callData, callData, callData]))
          .to.be.revertedWith("PairTradingLayer: Only two cellData can be there in send quote functions");
      });


      it("Should pair two sendQuotes", async () => {
        let request = limitQuoteRequestBuilder().build();
        let callData = context.partyAFacet.interface.encodeFunctionData("sendQuote",
          await getListFormat(request));

        await layer.connect(context.signers.user).partyACall(partyAAccount, [callData, callData]);

        expect(await layer.abPairs(1)).to.be.equal(2);
        expect(await layer.baPairs(2)).to.be.equal(1);
      });

      describe("Testing Pair functions", function() {
        beforeEach(async () => {
          let quoteRequest1 = limitQuoteRequestBuilder().build();
          let sendQuote1 = context.partyAFacet.interface.encodeFunctionData("sendQuote",
            await getListFormat(quoteRequest1));

          let quoteRequest2 = limitQuoteRequestBuilder().positionType(PositionType.SHORT).build();
          let sendQuote2 = context.partyAFacet.interface.encodeFunctionData("sendQuote",
            await getListFormat(quoteRequest2));

          await layer.connect(context.signers.user).partyACall(partyAAccount, [sendQuote1, sendQuote2]);

          let allocate = context.accountFacet.interface.encodeFunctionData("allocateForPartyB",
            [decimal(500), partyAAccount],
          );
          layer.connect(context.signers.user).partyBCall(partyBAccount, [allocate]);
        });

        it("Should not be able to call pair functions only for one quote", async () => {
          let lockQuote = context.partyBFacet.interface.encodeFunctionData("lockQuote",
            [1, await getDummySingleUpnlSig()],
          );
          await expect(layer.connect(context.signers.user).partyBCall(partyBAccount, [lockQuote])).to.be.revertedWith(
            "PairTradingLayer: Can't perform on only one quote from a pair",
          );
        });

        it("Should be able to call pair functions only for pair quotes", async () => {
          let lockQuote1 = context.partyBFacet.interface.encodeFunctionData("lockQuote",
            [1, await getDummySingleUpnlSig()],
          );
          let lockQuote2 = context.partyBFacet.interface.encodeFunctionData("lockQuote",
            [2, await getDummySingleUpnlSig()],
          );
          await layer.connect(context.signers.user).partyBCall(partyBAccount, [lockQuote1, lockQuote2]);
        });

      });
    });

  });
}
















