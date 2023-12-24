// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";
import "./IInstantExecEvents.sol";
import "./InstantExecFacetImpl.sol";
import "../../storages/QuoteStorage.sol";

contract InstantExecFacet is Accessibility, Pausable, IInstantExecEvents {
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
    ) external whenNotPartyBActionsPaused onlyPartyBOfQuote(quoteId) notLiquidated(quoteId) {
        InstantExecFacetImpl.instantClose(
            quoteId,
            requestedClosePrice,
            quantityToClose,
            orderType,
            deadline,
            filledAmount,
            closedPrice,
            partyASig,
            upnlSig
        );
        Quote storage quote = QuoteStorage.layout().quotes[quoteId];
        emit InstantFillCloseRequest(
            quoteId,
            quote.partyA,
            quote.partyB,
            filledAmount,
            closedPrice,
            quote.quoteStatus
        );
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
    ) external whenNotPartyBActionsPaused onlyPartyB notLiquidated(quoteId) {
        InstantExecFacetImpl.instantOpen(
            partyA,
            partyB,
            symbolId,
            positionType,
            orderType,
            price,
            quantity,
            cva,
            lf,
            partyAmm,
            partyBmm,
            maxFundingRate,
            deadline,
            filledAmount,
            openedPrice,
            partyASig,
            upnlSig
        );
    }
}
