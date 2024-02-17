// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../storages/GlobalAppStorage.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/BridgeStorage.sol";
import "../../storages/MAStorage.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

library BridgeFacetImpl {
    using SafeERC20 for IERC20;

    function transferToBridge(address user, uint256 amount, address bridge) internal {
        GlobalAppStorage.Layout storage appLayout = GlobalAppStorage.layout();
        BridgeStorage.Layout storage bridgeLayout = BridgeStorage.layout();

        require(bridgeLayout.bridges[bridge], "BridgeFacet: Invalid bridge");
        require(bridge != user, "BridgeFacet: Bridge and user can't be the same");

        uint256 decimal = (1e18 - (10 ** IERC20Metadata(appLayout.collateral).decimals()));
        uint256 amountWith18Decimals = (decimal == 0 ? 1 : decimal) * amount;
        uint256 currentId = ++bridgeLayout.lastId;

        BridgeTransaction memory bridgeTransaction = BridgeTransaction({
            id: currentId,
            amount: amountWith18Decimals,
            user: user,
            bridge: bridge,
            timestamp: block.timestamp,
            status: BridgeTransactionStatus.RECEIVED
        });
        AccountStorage.layout().balances[user] -= amountWith18Decimals;

        bridgeLayout.bridgeTransactions[currentId] = bridgeTransaction;
    }

    function withdrawReceivedBridgeValue(uint256 transactionId) internal {
        GlobalAppStorage.Layout storage appLayout = GlobalAppStorage.layout();
        BridgeStorage.Layout storage bridgeLayout = BridgeStorage.layout();

        BridgeTransaction storage bridgeTransaction = bridgeLayout.bridgeTransactions[transactionId];

        require(bridgeTransaction.status == BridgeTransactionStatus.RECEIVED, "BridgeFacet: Already withdrawn");
        require(block.timestamp >= MAStorage.layout().deallocateCooldown + bridgeTransaction.timestamp, "BridgeFacet: Cooldown hasn't reached");
        require(msg.sender == bridgeTransaction.bridge, "BridgeFacet: Sender is not the transaction's bridge");

        bridgeTransaction.status = BridgeTransactionStatus.WITHDRAWN;
        IERC20(appLayout.collateral).safeTransfer(bridgeTransaction.bridge, bridgeTransaction.amount);
    }
}
