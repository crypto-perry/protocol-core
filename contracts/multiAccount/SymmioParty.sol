// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

contract SymmioParty {
    address public symmioAddress;
    address public multiAccountAddress;

    constructor(address multiAccountAddress_, address symmioAddress_) {
        require(
            multiAccountAddress_ != address(0) && symmioAddress_ != address(0),
            "SymmioParty: Zero Address"
        );
        multiAccountAddress = multiAccountAddress_;
        symmioAddress = symmioAddress_;
    }

    function _call(
        bytes memory _callData
    ) external returns (bool _success, bytes memory _resultData) {
        require(msg.sender == multiAccountAddress, "SymmioParty: Sender should be MultiAccount");
        return symmioAddress.call{ value: 0 }(_callData);
    }
}
