// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../facets/Account/IAccountFacet.sol";
import "../facets/control/IControlFacet.sol";
import "../facets/FundingRate/IFundingRateFacet.sol";
import "../facets/liquidation/ILiquidationFacet.sol";
import "../facets/PartyA/IPartyAFacet.sol";
import "../facets/PartyB/IPartyBFacet.sol";
import "../facets/IViewFacet.sol";
import { IDiamondCut } from "./IDiamondCut.sol";
import { IDiamondLoupe } from "./IDiamondLoupe.sol";

interface IDiamondAllFacets is
    IAccountFacet,
    IControlFacet,
    IFundingRateFacet,
    IPartyBFacet,
    IPartyAFacet,
    IDiamondCut,
    IDiamondLoupe,
    IViewFacet
{}
