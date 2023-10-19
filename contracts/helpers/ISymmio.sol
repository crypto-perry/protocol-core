// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;


interface ISymmio {
    struct PublicKey {
        uint256 x;
        uint8 parity;
    }

    function registerPartyB(address partyB) external;

    function setMuonIds(
        uint256 muonAppId,
        address validGateway,
        PublicKey memory publicKey
    ) external;

    function setCollateral(address collateral) external;

    function setLiquidatorShare(uint256 liquidatorShare) external;

    function setPendingQuotesValidLength(uint256 pendingQuotesValidLength) external;

    function setFeeCollector(address feeCollector) external;

    function setBalanceLimitPerUser(uint256 balanceLimitPerUser) external;

    // Symbol
    function setSymbolValidationState(uint256 symbolId, bool isValid) external;

    function setSymbolMaxLeverage(uint256 symbolId, uint256 maxLeverage) external;

    function setSymbolAcceptableValues(
        uint256 symbolId,
        uint256 minAcceptableQuoteValue,
        uint256 minAcceptablePortionLF
    ) external;

    function setSymbolTradingFee(uint256 symbolId, uint256 tradingFee) external;

    // Cooldowns
    function setDeallocateCooldown(uint256 deallocateCooldown) external;

    function setForceCancelCooldown(uint256 forceCancelCooldown) external;

    function setForceCloseCooldown(uint256 forceCloseCooldown) external;

    function setForceCancelCloseCooldown(uint256 forceCancelCloseCooldown) external;

    function setForceCloseGapRatio(uint256 forceCloseGapRatio) external;

    function setLiquidationTimeout(uint256 liquidationTimeout) external;
}
