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

    struct Condition {
        string errorMessage;
        uint256 startIdx;
        uint256 expectedValue;
    }

    event SetPartyImplementation(bytes oldAddress, bytes newAddress);
    event SetSymmioAddress(address oldAddress, address newAddress);
    event CreatePartyAAccount(address user, address account, string name);
    event CreatePartyBAccount(address user, address account, address[] trustedAddresses);
    event AddTrustedAddressesToPartyBAccount(address user, address account, address[] trustedAddresses);
    event RemoveTrustedAddressesFromPartyBAccount(address user, address account, address[] trustedAddresses);
    event AddAdminAddressesToPartyBAccount(address user, address account, address[] admins);
    event RemoveAdminAddressesFromPartyBAccount(address user, address account, address[] admins);
    event EditPartyAAccountName(address user, address account, string newName);
    event Call(address user, address account, bytes _callData, bool _success, bytes _resultData);
}
