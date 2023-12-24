// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../storages/AccountStorage.sol";

library LibSig {
    using ECDSA for bytes32;

    function getChainId() internal view returns (uint256 id) {
        assembly {
            id := chainid()
        }
    }

    function verifySig(
        bytes32 hash,
        bytes memory signature
    ) internal view returns (address signer) {
        hash = hash.toEthSignedMessageHash();
        signer = hash.recover(signature);
    }

    function verifyRequestToCloseSig(
        uint256 quoteId,
        uint256 requestedClosePrice,
        uint256 quantityToClose,
        OrderType orderType,
        uint256 deadline,
        bytes memory signature,
        address partyA
    ) internal view {
        require(!AccountStorage.layout().usedSignature[signature], "LibSig: Used Signature");
        bytes32 hash = keccak256(
            abi.encodePacked(
                address(this),
                "requestToClose",
                quoteId,
                requestedClosePrice,
                quantityToClose,
                orderType,
                deadline,
                getChainId()
            )
        );
        address signer = verifySig(hash, signature);
        require(signer == partyA, "LibSig: Invalid Signer");
    }
}
