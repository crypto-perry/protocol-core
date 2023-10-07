// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

interface IPairTradingLayer {
    struct Account {
        address accountAddress;
        string name;
    }

    event SetPartyImplementation(bytes oldAddress, bytes newAddress);
    event SetSymmioAddress(address oldAddress, address newAddress);
    event CreatePartyAAccount(address user, address account, string name);
    event CreatePartyBAccount(address account, address[] trustedAddresses);
    event AddTrustedAddressesToPartyBAccount(address account, address[] trustedAddresses);
    event RemoveTrustedAddressOfPartyBAccount(address account, address trustedAddress);
    event EditPartyAAccountName(address user, address account, string newName);
    event Call(address user, address account, bytes _callData, bool _success, bytes _resultData);
}
