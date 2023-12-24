// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

interface IInstantExecEvents {
    event InstantFillCloseRequest(
        uint256 quoteId,
        address partyA,
        address partyB,
        uint256 filledAmount,
        uint256 closedPrice,
        QuoteStatus quoteStatus
    );
}