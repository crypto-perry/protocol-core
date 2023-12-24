// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/LibLockedValues.sol";
import "../../libraries/LibMuon.sol";
import "../../libraries/LibSig.sol";
import "../../libraries/LibAccount.sol";
import "../../libraries/LibSolvency.sol";
import "../../libraries/LibQuote.sol";
import "../../libraries/LibPartyB.sol";
import "../../storages/MAStorage.sol";
import "../../storages/QuoteStorage.sol";
import "../../storages/MuonStorage.sol";
import "../../storages/GlobalAppStorage.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/SymbolStorage.sol";

library InstantExecFacetImpl {
    using LockedValuesOps for LockedValues;

    function instantClose(
        uint256 quoteId,
        uint256 requestedClosePrice,
        uint256 quantityToClose,
        OrderType orderType,
        uint256 deadline,
        uint256 filledAmount,
        uint256 closedPrice,
        bytes memory partyASig,
        PairUpnlAndPriceSig memory upnlSig
    ) internal {
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();
        Quote storage quote = QuoteStorage.layout().quotes[quoteId];
        LibSig.verifyRequestToCloseSig(
            quoteId,
            requestedClosePrice,
            quantityToClose,
            orderType,
            deadline,
            partyASig,
            quote.partyA
        );
        accountLayout.usedSignature[partyASig] = true;

        LibMuon.verifyPairUpnlAndPrice(upnlSig, quote.partyB, quote.partyA, quote.symbolId);

        // request to close process
        require(quote.quoteStatus == QuoteStatus.OPENED, "InstantExecFacet: Invalid state");
        require(deadline >= block.timestamp, "InstantExecFacet: Low deadline");
        require(
            LibQuote.quoteOpenAmount(quote) >= quantityToClose,
            "InstantExecFacet: Invalid quantityToClose"
        );

        // check that remaining position is not too small
        if (LibQuote.quoteOpenAmount(quote) > quantityToClose) {
            require(
                ((LibQuote.quoteOpenAmount(quote) - quantityToClose) *
                    quote.lockedValues.totalForPartyA()) /
                    LibQuote.quoteOpenAmount(quote) >=
                    SymbolStorage.layout().symbols[quote.symbolId].minAcceptableQuoteValue,
                "InstantExecFacet: Remaining quote value is low"
            );
        }

        quote.quoteStatus = QuoteStatus.CLOSE_PENDING;
        quote.requestedClosePrice = requestedClosePrice;
        quote.quantityToClose = quantityToClose;
        quote.orderType = orderType;
        quote.deadline = deadline;

        // close process
        if (quote.positionType == PositionType.LONG) {
            require(
                closedPrice >= quote.requestedClosePrice,
                "InstantExecFacet: Closed price isn't valid"
            );
        } else {
            require(
                closedPrice <= quote.requestedClosePrice,
                "InstantExecFacet: Closed price isn't valid"
            );
        }
        if (quote.orderType == OrderType.LIMIT) {
            require(
                quote.quantityToClose >= filledAmount,
                "InstantExecFacet: Invalid filledAmount"
            );
        } else {
            require(quote.quantityToClose == filledAmount, "PartyBFacet: Invalid filledAmount");
        }

        LibSolvency.isSolventAfterClosePosition(quoteId, filledAmount, closedPrice, upnlSig);
        accountLayout.partyBNonces[quote.partyB][quote.partyA] += 1;
        accountLayout.partyANonces[quote.partyA] += 1;
        LibQuote.closeQuote(quote, filledAmount, closedPrice);
    }

    function instantOpen(
        address partyA,
        address partyB,
        uint256 symbolId,
        PositionType positionType,
        OrderType orderType,
        uint256 price,
        uint256 quantity,
        uint256 cva,
        uint256 lf,
        uint256 partyAmm,
        uint256 partyBmm,
        uint256 maxFundingRate,
        uint256 deadline,
        uint256 filledAmount,
        uint256 openedPrice,
        bytes memory partyASig,
        PairUpnlAndPriceSig memory upnlSig
    ) internal {
        QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();
        MAStorage.Layout storage maLayout = MAStorage.layout();
        SymbolStorage.Layout storage symbolLayout = SymbolStorage.layout();

        require(
            quoteLayout.partyAPendingQuotes[partyA].length < maLayout.pendingQuotesValidLength,
            "PartyAFacet: Number of pending quotes out of range"
        );
        require(symbolLayout.symbols[symbolId].isValid, "PartyAFacet: Symbol is not valid");
        require(deadline >= block.timestamp, "PartyAFacet: Low deadline");

        LockedValues memory lockedValues = LockedValues(cva, lf, partyAmm, partyBmm);
        uint256 tradingPrice = orderType == OrderType.LIMIT ? price : upnlSig.price;

        require(
            lockedValues.lf >=
                (symbolLayout.symbols[symbolId].minAcceptablePortionLF *
                    lockedValues.totalForPartyA()) /
                    1e18,
            "PartyAFacet: LF is not enough"
        );

        require(
            lockedValues.totalForPartyA() >= symbolLayout.symbols[symbolId].minAcceptableQuoteValue,
            "PartyAFacet: Quote value is low"
        );
        require(partyB != partyA, "PartyAFacet: Sender isn't allowed in partyBWhiteList");

        LibMuon.verifyPartyAUpnlAndPrice(upnlSig, partyA, symbolId);

        int256 availableBalance = LibAccount.partyAAvailableForQuote(upnlSig.upnl, partyA);
        require(availableBalance > 0, "PartyAFacet: Available balance is lower than zero");
        require(
            uint256(availableBalance) >=
                lockedValues.totalForPartyA() +
                    ((quantity * tradingPrice * symbolLayout.symbols[symbolId].tradingFee) / 1e36),
            "PartyAFacet: insufficient available balance"
        );

        // lock funds the in middle of way
        accountLayout.pendingLockedBalances[partyA].add(lockedValues);
        currentId = ++quoteLayout.lastId;
        // accountLayout.partyANonces[msg.sender] += 1;

        // create quote.
        Quote memory quote = Quote({
            id: currentId,
            partyBsWhiteList: partyBsWhiteList,
            symbolId: symbolId,
            positionType: positionType,
            orderType: orderType,
            openedPrice: 0,
            initialOpenedPrice: 0,
            requestedOpenPrice: price,
            marketPrice: upnlSig.price,
            quantity: quantity,
            closedAmount: 0,
            lockedValues: lockedValues,
            initialLockedValues: lockedValues,
            maxFundingRate: maxFundingRate,
            partyA: partyA,
            partyB: address(0),
            quoteStatus: QuoteStatus.PENDING,
            avgClosedPrice: 0,
            requestedClosePrice: 0,
            parentId: 0,
            createTimestamp: block.timestamp,
            statusModifyTimestamp: block.timestamp,
            quantityToClose: 0,
            lastFundingPaymentTimestamp: 0,
            deadline: deadline,
            tradingFee: symbolLayout.symbols[symbolId].tradingFee
        });
        quoteLayout.quoteIdsOf[partyA].push(currentId);
        quoteLayout.partyAPendingQuotes[partyA].push(currentId);
        quoteLayout.quotes[currentId] = quote;

        accountLayout.allocatedBalances[partyA] -= LibQuote.getTradingFee(currentId);

        // =========================================================================================

        LibMuon.verifyPartyBUpnl(upnlSig, msg.sender, quote.partyA);
        LibPartyB.checkPartyBValidationToLockQuote(quoteId, upnlSig.upnl);
        if (increaseNonce) {
            accountLayout.partyBNonces[msg.sender][quote.partyA] += 1;
        }
        quote.statusModifyTimestamp = block.timestamp;
        quote.quoteStatus = QuoteStatus.LOCKED;
        quote.partyB = msg.sender;
        // lock funds for partyB
        accountLayout.partyBPendingLockedBalances[msg.sender][quote.partyA].addQuote(quote);
        quoteLayout.partyBPendingQuotes[msg.sender][quote.partyA].push(quote.id);

        // ===========================================================================================
        require(
            accountLayout.suspendedAddresses[quote.partyA] == false,
            "PartyBFacet: PartyA is suspended"
        );
        require(
            SymbolStorage.layout().symbols[quote.symbolId].isValid,
            "PartyBFacet: Symbol is not valid"
        );
        require(
            !AccountStorage.layout().suspendedAddresses[msg.sender],
            "PartyBFacet: Sender is Suspended"
        );

        require(
            !GlobalAppStorage.layout().partyBEmergencyStatus[quote.partyB],
            "PartyBFacet: PartyB is in emergency mode"
        );
        require(
            !GlobalAppStorage.layout().emergencyMode,
            "PartyBFacet: System is in emergency mode"
        );

        require(
            quote.quoteStatus == QuoteStatus.LOCKED ||
                quote.quoteStatus == QuoteStatus.CANCEL_PENDING,
            "PartyBFacet: Invalid state"
        );
        require(block.timestamp <= quote.deadline, "PartyBFacet: Quote is expired");
        if (quote.orderType == OrderType.LIMIT) {
            require(
                quote.quantity >= filledAmount && filledAmount > 0,
                "PartyBFacet: Invalid filledAmount"
            );
            accountLayout.balances[GlobalAppStorage.layout().feeCollector] +=
                (filledAmount * quote.requestedOpenPrice * quote.tradingFee) /
                1e36;
        } else {
            require(quote.quantity == filledAmount, "PartyBFacet: Invalid filledAmount");
            accountLayout.balances[GlobalAppStorage.layout().feeCollector] +=
                (filledAmount * quote.marketPrice * quote.tradingFee) /
                1e36;
        }
        if (quote.positionType == PositionType.LONG) {
            require(
                openedPrice <= quote.requestedOpenPrice,
                "PartyBFacet: Opened price isn't valid"
            );
        } else {
            require(
                openedPrice >= quote.requestedOpenPrice,
                "PartyBFacet: Opened price isn't valid"
            );
        }
        LibMuon.verifyPairUpnlAndPrice(upnlSig, quote.partyB, quote.partyA, quote.symbolId);

        quote.openedPrice = openedPrice;
        quote.initialOpenedPrice = openedPrice;

        accountLayout.partyANonces[quote.partyA] += 1;
        accountLayout.partyBNonces[quote.partyB][quote.partyA] += 1;
        quote.statusModifyTimestamp = block.timestamp;

        LibQuote.removeFromPendingQuotes(quote);

        if (quote.quantity == filledAmount) {
            accountLayout.pendingLockedBalances[quote.partyA].subQuote(quote);
            accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuote(quote);
            quote.lockedValues.mul(openedPrice).div(quote.requestedOpenPrice);

            // check locked values
            require(
                quote.lockedValues.totalForPartyA() >=
                    SymbolStorage.layout().symbols[quote.symbolId].minAcceptableQuoteValue,
                "PartyBFacet: Quote value is low"
            );
        }
        // partially fill
        else {
            currentId = ++quoteLayout.lastId;
            QuoteStatus newStatus;
            if (quote.quoteStatus == QuoteStatus.CANCEL_PENDING) {
                newStatus = QuoteStatus.CANCELED;
            } else {
                newStatus = QuoteStatus.PENDING;
                quoteLayout.partyAPendingQuotes[quote.partyA].push(currentId);
            }
            LockedValues memory filledLockedValues = LockedValues(
                (quote.lockedValues.cva * filledAmount) / quote.quantity,
                (quote.lockedValues.lf * filledAmount) / quote.quantity,
                (quote.lockedValues.partyAmm * filledAmount) / quote.quantity,
                (quote.lockedValues.partyBmm * filledAmount) / quote.quantity
            );
            LockedValues memory appliedFilledLockedValues = filledLockedValues;
            appliedFilledLockedValues = appliedFilledLockedValues.mulMem(openedPrice);
            appliedFilledLockedValues = appliedFilledLockedValues.divMem(quote.requestedOpenPrice);
            // check that opened position is not minor position
            require(
                appliedFilledLockedValues.totalForPartyA() >=
                    SymbolStorage.layout().symbols[quote.symbolId].minAcceptableQuoteValue,
                "PartyBFacet: Quote value is low"
            );
            // check that new pending position is not minor position
            require(
                (quote.lockedValues.totalForPartyA() - filledLockedValues.totalForPartyA()) >=
                    SymbolStorage.layout().symbols[quote.symbolId].minAcceptableQuoteValue,
                "PartyBFacet: Quote value is low"
            );

            Quote memory q = Quote({
                id: currentId,
                partyBsWhiteList: quote.partyBsWhiteList,
                symbolId: quote.symbolId,
                positionType: quote.positionType,
                orderType: quote.orderType,
                openedPrice: 0,
                initialOpenedPrice: 0,
                requestedOpenPrice: quote.requestedOpenPrice,
                marketPrice: quote.marketPrice,
                quantity: quote.quantity - filledAmount,
                closedAmount: 0,
                lockedValues: LockedValues(0, 0, 0, 0),
                initialLockedValues: LockedValues(0, 0, 0, 0),
                maxFundingRate: quote.maxFundingRate,
                partyA: quote.partyA,
                partyB: address(0),
                quoteStatus: newStatus,
                avgClosedPrice: 0,
                requestedClosePrice: 0,
                parentId: quote.id,
                createTimestamp: quote.createTimestamp,
                statusModifyTimestamp: block.timestamp,
                quantityToClose: 0,
                lastFundingPaymentTimestamp: 0,
                deadline: quote.deadline,
                tradingFee: quote.tradingFee
            });

            quoteLayout.quoteIdsOf[quote.partyA].push(currentId);
            quoteLayout.quotes[currentId] = q;
            Quote storage newQuote = quoteLayout.quotes[currentId];

            if (newStatus == QuoteStatus.CANCELED) {
                // send trading Fee back to partyA
                accountLayout.allocatedBalances[newQuote.partyA] += LibQuote.getTradingFee(
                    newQuote.id
                );
                // part of quote has been filled and part of it has been canceled
                accountLayout.pendingLockedBalances[quote.partyA].subQuote(quote);
                accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuote(
                    quote
                );
            } else {
                accountLayout.pendingLockedBalances[quote.partyA].sub(filledLockedValues);
                accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuote(
                    quote
                );
            }
            newQuote.lockedValues = quote.lockedValues.sub(filledLockedValues);
            newQuote.initialLockedValues = newQuote.lockedValues;
            quote.quantity = filledAmount;
            quote.lockedValues = appliedFilledLockedValues;
        }
        // lock with amount of filledAmount
        accountLayout.lockedBalances[quote.partyA].addQuote(quote);
        accountLayout.partyBLockedBalances[quote.partyB][quote.partyA].addQuote(quote);

        LibSolvency.isSolventAfterOpenPosition(quoteId, filledAmount, upnlSig);
        // check leverage (is in 18 decimals)
        require(
            (quote.quantity * quote.openedPrice) / quote.lockedValues.totalForPartyA() <=
                SymbolStorage.layout().symbols[quote.symbolId].maxLeverage,
            "PartyBFacet: Leverage is high"
        );

        quote.quoteStatus = QuoteStatus.OPENED;
        LibQuote.addToOpenPositions(quoteId);
    }
}
