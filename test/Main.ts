import { shouldBehaveLikePairTradingLayer } from "./PairTradingLayer.test";
import { shouldBehaveLikeFuzzTest } from "./FuzzTest.behavior";
import { shouldBehaveLikeSpecificScenario } from "./SpecificScenario.behavior";
import { shouldBehaveLikeFundingRate } from "./FundingRate.behavior";
import { shouldBehaveLikeLiquidationFacet } from "./LiquidationFacet.behavior";
import { shouldBehaveLikeClosePosition } from "./ClosePosition.behavior";
import { shouldBehaveLikeCancelQuote } from "./CancelQuote.behavior";
import { shouldBehaveLikeOpenPosition } from "./OpenPosition.behavior";
import { shouldBehaveLikeLockQuote } from "./LockQuote.behavior";
import { shouldBehaveLikeSendQuote } from "./SendQuote.behavior";
import { shouldBehaveLikeAccountFacet } from "./AccountFacet.behavior";
import { shouldBehaveLikeDiamond } from "./Diamond.behavior";

describe("UnitTests", function() {
  if (process.env.TEST_MODE == "static") {
    describe("Diamond", async function() {
      shouldBehaveLikeDiamond();
    });

    describe("AccountFacet", async function() {
      shouldBehaveLikeAccountFacet();
    });

    describe("SendQuote", async function() {
      shouldBehaveLikeSendQuote();
    });

    describe("LockQuote", async function() {
      shouldBehaveLikeLockQuote();
    });

    describe("OpenPosition", async function() {
      shouldBehaveLikeOpenPosition();
    });

    describe("CancelQuote", async function() {
      shouldBehaveLikeCancelQuote();
    });

    describe("ClosePosition", async function() {
      shouldBehaveLikeClosePosition();
    });

    describe("Liquidation", async function() {
      shouldBehaveLikeLiquidationFacet();
    });

    describe("FundingRate", async function() {
      shouldBehaveLikeFundingRate();
    });

    describe("SpecificScenario", async function() {
      shouldBehaveLikeSpecificScenario();
    });

    describe("PairTradingLayer", async function() {
      shouldBehaveLikePairTradingLayer();
    });

  } else if (process.env.TEST_MODE == "fuzz") {
    describe("FuzzTest", async function() {
      shouldBehaveLikeFuzzTest();
    });
  } else {
    throw new Error("Invalid TEST_MODE property. should be static or fuzz");
  }
});
