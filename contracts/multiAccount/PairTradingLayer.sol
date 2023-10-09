// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/ISymmio.sol";
import "../interfaces/ISymmioParty.sol";
import "../interfaces/IPairTradingLayer.sol";

contract PairTradingLayer is
    IPairTradingLayer,
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Defining roles for access control
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    // State variables
    mapping(address => Account[]) public accounts; // User to their accounts mapping
    mapping(address => uint256) public indexOfAccount; // Account to its index mapping
    mapping(address => address) public partyAOwners; // Account to its owner mapping
    mapping(address => mapping(address => bool)) public partyBTrustedAddress; // Account to its trusted addresses
    mapping(address => mapping(address => bool)) public partyBAdminAddress; // Account to its admin addresses

    mapping(uint256 => uint256) public abPairs;
    mapping(uint256 => uint256) public baPairs;

    mapping(bytes4 => uint256) public pairOpsSelectors; // Function selector -> index of quoteId in callData
    mapping(bytes4 => Condition[]) public additionalConditions; // Function selector -> conditions
    bytes4 public sendQuoteSelector;

    address public symmioAddress; // Address of the Symmio platform
    uint256 public saltCounter; // Counter for generating unique addresses with create2
    bytes public partyImplementation;

    modifier onlyOwner(address account, address sender) {
        require(partyAOwners[account] == sender, "PairTradingLayer: Sender isn't owner of account");
        _;
    }

    modifier onlyPartyBTrusted(address account, address sender) {
        require(
            partyBTrustedAddress[account][sender],
            "PairTradingLayer: Sender isn't trusted by this party"
        );
        _;
    }

    modifier onlyPartyBAdmin(address account, address sender) {
        require(
            partyBAdminAddress[account][sender],
            "PairTradingLayer: Sender isn't admin for this party"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address symmioAddress_) public initializer {
        __Pausable_init();
        __AccessControl_init();

        require(admin != address(0), "PairTradingLayer: Zero address");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(UNPAUSER_ROLE, admin);
        _grantRole(SETTER_ROLE, admin);
        symmioAddress = symmioAddress_;
    }

    function addPairOpsSelector(
        bytes4 selector,
        uint256 quoteIdIndex
    ) external onlyRole(SETTER_ROLE) {
        pairOpsSelectors[selector] = quoteIdIndex;
    }

    function addAdditionalCondition(
        bytes4 selector,
        Condition memory condition
    ) external onlyRole(SETTER_ROLE) {
        additionalConditions[selector].push(condition);
    }

    function removeAdditionalCondition(bytes4 selector, uint256 index) external onlyRole(SETTER_ROLE) {
        require(index < additionalConditions[selector].length, "Invalid index");
        // If there's only one condition, just pop it
        if (additionalConditions[selector].length == 1) {
            additionalConditions[selector].pop();
            return;
        }
        // Move the last condition into the place of the one to delete
        additionalConditions[selector][index] = additionalConditions[selector][additionalConditions[selector].length - 1];
        // Remove the last condition
        additionalConditions[selector].pop();
    }


    function setSendQuoteSelector(bytes4 selector) external onlyRole(SETTER_ROLE) {
        sendQuoteSelector = selector;
    }

    function setPartyImplementation(bytes memory impl_) external onlyRole(SETTER_ROLE) {
        partyImplementation = impl_;
        emit SetPartyImplementation(partyImplementation, impl_);
    }

    function setSymmioAddress(address addr) external onlyRole(SETTER_ROLE) {
        require(addr != address(0), "PairTradingLayer: Zero address");
        symmioAddress = addr;
        emit SetSymmioAddress(symmioAddress, addr);
    }

    function _deployParty() internal returns (address contractAddress) {
        bytes32 salt = keccak256(abi.encodePacked("PairTradingLayer_", saltCounter));
        saltCounter += 1;
        bytes memory bytecode = abi.encodePacked(
            partyImplementation,
            abi.encode(address(this), symmioAddress)
        );
        assembly {
            contractAddress := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        require(contractAddress != address(0), "PairTradingLayer: create2 failed");
        return contractAddress;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    //////////////////////////////// Account Management ////////////////////////////////////

    function createPartyAAccount(string memory name) external whenNotPaused {
        address account = _deployParty();
        indexOfAccount[account] = accounts[msg.sender].length;
        accounts[msg.sender].push(Account(account, name));
        partyAOwners[account] = msg.sender;
        emit CreatePartyAAccount(msg.sender, account, name);
    }

    function editPartyAAccountName(
        address accountAddress,
        string memory name
    ) external onlyOwner(accountAddress, msg.sender) whenNotPaused {
        uint256 index = indexOfAccount[accountAddress];
        accounts[msg.sender][index].name = name;
        emit EditPartyAAccountName(msg.sender, accountAddress, name);
    }

    function createPartyBAccount(
        address[] memory trustedAddresses
    ) external whenNotPaused returns (address account) {
        account = _deployParty();
        partyBAdminAddress[account][msg.sender] = true;
        for (uint8 i = 0; i < trustedAddresses.length; i++) {
            require(trustedAddresses[i] != address(0), "PairTradingLayer: Zero address");
            partyBTrustedAddress[account][trustedAddresses[i]] = true;
        }
        // TODO: have a list for all partyBs
        emit CreatePartyBAccount(msg.sender, account, trustedAddresses);
    }

    function addTrustedAddressToPartyBAccount(
        address account,
        address[] memory trustedAddresses
    ) external whenNotPaused onlyPartyBAdmin(account, msg.sender) {
        for (uint8 i = 0; i < trustedAddresses.length; i++) {
            require(trustedAddresses[i] != address(0), "PairTradingLayer: Zero address");
            partyBTrustedAddress[account][trustedAddresses[i]] = true;
        }
        emit AddTrustedAddressesToPartyBAccount(msg.sender, account, trustedAddresses);
    }

    function removeTrustedAddressFromPartyBAccount(
        address account,
        address[] memory trustedAddresses
    ) external whenNotPaused onlyPartyBAdmin(account, msg.sender) {
        for (uint8 i = 0; i < trustedAddresses.length; i++) {
            require(trustedAddresses[i] != address(0), "PairTradingLayer: Zero address");
            partyBTrustedAddress[account][trustedAddresses[i]] = false;
        }
        emit RemoveTrustedAddressesFromPartyBAccount(msg.sender, account, trustedAddresses);
    }

    function addAdminAddressToPartyBAccount(
        address account,
        address[] memory admins
    ) external whenNotPaused onlyPartyBAdmin(account, msg.sender) {
        for (uint8 i = 0; i < admins.length; i++) {
            require(admins[i] != address(0), "PairTradingLayer: Zero address");
            partyBAdminAddress[account][admins[i]] = true;
        }
        emit AddAdminAddressesToPartyBAccount(msg.sender, account, admins);
    }

    function removeAdminAddressFromPartyBAccount(
        address account,
        address[] memory admins
    ) external whenNotPaused onlyPartyBAdmin(account, msg.sender) {
        for (uint8 i = 0; i < admins.length; i++) {
            require(admins[i] != address(0), "PairTradingLayer: Zero address");
            partyBAdminAddress[account][admins[i]] = false;
        }
        emit RemoveAdminAddressesFromPartyBAccount(msg.sender, account, admins);
    }

    function depositForAccount(address account, uint256 amount) external whenNotPaused {
        address collateral = ISymmio(symmioAddress).getCollateral();
        IERC20Upgradeable(collateral).safeTransferFrom(msg.sender, address(this), amount);
        IERC20Upgradeable(collateral).safeApprove(symmioAddress, amount);
        ISymmio(symmioAddress).depositFor(account, amount);
    }

    function depositAndAllocateForPartyAAccount(
        address account,
        uint256 amount
    ) external onlyOwner(account, msg.sender) whenNotPaused {
        address collateral = ISymmio(symmioAddress).getCollateral();
        IERC20Upgradeable(collateral).safeTransferFrom(msg.sender, address(this), amount);
        IERC20Upgradeable(collateral).safeApprove(symmioAddress, amount);
        ISymmio(symmioAddress).depositFor(account, amount);
        uint256 amountWith18Decimals = (amount * 1e18) /
            (10 ** IERC20Metadata(collateral).decimals());
        bytes memory _callData = abi.encodeWithSignature("allocate(uint256)", amountWith18Decimals);
        innerCall(account, _callData);
    }

    function withdrawFromAccountPartyA(
        address account,
        uint256 amount
    ) external onlyOwner(account, msg.sender) whenNotPaused {
        bytes memory _callData = abi.encodeWithSignature(
            "withdrawTo(address,uint256)",
            partyAOwners[account],
            amount
        );
        innerCall(account, _callData);
    }

    function withdrawFromAccountPartyB(
        address account,
        uint256 amount,
        address destination
    ) external onlyPartyBAdmin(account, msg.sender) whenNotPaused {
        bytes memory _callData = abi.encodeWithSignature(
            "withdrawTo(address,uint256)",
            destination,
            amount
        );
        innerCall(account, _callData);
    }

    function innerCall(address account, bytes memory _callData) internal {
        (bool _success, bytes memory _resultData) = ISymmioParty(account)._call(_callData);
        emit Call(msg.sender, account, _callData, _success, _resultData);
        require(_success, "PairTradingLayer: Error occurred");
    }

    function partyACall(
        address account,
        bytes[] memory _callDatas
    ) external onlyOwner(account, msg.sender) whenNotPaused {
        return _call(account, _callDatas);
    }

    function partyBCall(
        address account,
        bytes[] memory _callDatas
    ) external onlyPartyBTrusted(account, msg.sender) whenNotPaused {
        return _call(account, _callDatas);
    }

    function _call(address account, bytes[] memory _callDatas) internal {
        uint256[] memory quoteIds = new uint256[](_callDatas.length);
        uint256[] memory pairedQuoteIds = new uint256[](_callDatas.length);
        uint256 pairedCount = 0;

        for (uint8 i = 0; i < _callDatas.length; i++) {
            bytes memory _callData = _callDatas[i];
            require(_callData.length >= 4, "PairTradingLayer: Invalid call data");
            bytes4 functionSelector;
            assembly {
                functionSelector := mload(add(_callData, 0x20))
            }

            if (functionSelector == sendQuoteSelector && i == 0) {
                require(
                    _callDatas.length <= 2,
                    "PairTradingLayer: Only two cellData can be there in send quote functions"
                );
                uint256 quoteId = ISymmio(symmioAddress).getNextQuoteId();
                if (_callDatas.length == 2) {
                    bytes memory _secondCellData = _callDatas[1];
                    require(_secondCellData.length >= 4, "PairTradingLayer: Invalid call data");
                    bytes4 secondFunctionSelector;
                    assembly {
                        secondFunctionSelector := mload(add(_secondCellData, 0x20))
                    }
                    require(
                        secondFunctionSelector == sendQuoteSelector,
                        "PairTradingLayer: all cellDatas should be for send quote function"
                    );
                }
                uint256 secondQuoteId = quoteId + 1;
                abPairs[quoteId] = secondQuoteId;
                baPairs[secondQuoteId] = quoteId;
            } else {
                uint256 startIdx = pairOpsSelectors[functionSelector];
                if (startIdx > 0) {
                    require(
                        _callData.length >= startIdx + 32,
                        "PairTradingLayer: Data is too short"
                    );
                    uint256 quoteId;
                    assembly {
                        quoteId := mload(add(add(_callData, 32), startIdx))
                    }
                    uint256 pair = abPairs[quoteId];
                    if (pair == 0) pair = baPairs[quoteId];

                    if (pair > 0) {
                        quoteIds[i] = quoteId;
                        pairedQuoteIds[pairedCount] = pair;
                        pairedCount++;
                    }
                }
            }
            Condition[] storage conditions = additionalConditions[functionSelector];
            for (uint8 j = 0; j < conditions.length; j++) {
                uint256 realValue;
                uint256 startIdx = conditions[j].startIdx;
                assembly {
                    realValue := mload(add(add(_callData, 32), startIdx))
                }
                require(realValue == conditions[j].expectedValue, conditions[j].errorMessage);
            }
            innerCall(account, _callDatas[i]);
        }

        for (uint8 i = 0; i < pairedCount; i++) {
            bool found = false;
            for (uint8 j = 0; j < _callDatas.length; j++) {
                if (pairedQuoteIds[i] == quoteIds[j]) {
                    found = true;
                    break;
                }
            }
            require(found, "PairTradingLayer: Can't perform on only one quote from a pair");
        }
    }

    //////////////////////////////// VIEWS ////////////////////////////////////

    function getAccountsLength(address user) external view returns (uint256) {
        return accounts[user].length;
    }

    function getAccounts(
        address user,
        uint256 start,
        uint256 size
    ) external view returns (Account[] memory) {
        uint256 len = size > accounts[user].length - start ? accounts[user].length - start : size;
        Account[] memory userAccounts = new Account[](len);
        for (uint256 i = start; i < start + len; i++) {
            userAccounts[i - start] = accounts[user][i];
        }
        return userAccounts;
    }
}
