// SPDX-License-Identifier: MIT
// Cloned from @cofhe/mock-contracts/MockACL.sol:
//   1. `allow()` auto-registers the requester as handle owner on first call
//   2. `isAllowedWithPermission()` skips the EIP-712 `withPermission` check
//      because etched bytecode has uninitialised EIP-712 immutables
// solhint-disable-next-line transient-storage
pragma solidity >=0.8.25 <0.9.0;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MockPermissioned, Permission} from "@cofhe/mock-contracts/Permissioned.sol";
import {TASK_MANAGER_ADDRESS} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

contract ForgeMockACL is MockPermissioned {
    error AlreadyDelegated();
    error SenderCannotBeDelegateeAddress();
    error SenderNotAllowed(address sender);
    error DirectAllowForbidden(address sender);

    event AllowedForDecryption(uint256[] handlesList);
    event NewDelegation(address indexed sender, address indexed delegatee, address indexed contractAddress);

    /// @custom:storage-location erc7201:cofhe.storage.ACL
    struct ACLStorage {
        mapping(uint256 handle => bool isGlobal) globalHandles;
        mapping(uint256 handle => mapping(address account => bool isAllowed)) persistedAllowedPairs;
        mapping(uint256 => bool) allowedForDecryption;
        mapping(
            address account => mapping(address delegatee => mapping(address contractAddress => bool isDelegate))
        ) delegates;
    }

    string private constant CONTRACT_NAME = "ACL";
    uint256 private constant MAJOR_VERSION = 0;
    uint256 private constant MINOR_VERSION = 1;
    uint256 private constant PATCH_VERSION = 0;

    address public constant TASK_MANAGER_ADDRESS_ = TASK_MANAGER_ADDRESS;

    /// @dev keccak256(abi.encode(uint256(keccak256("cofhe.storage.ACL")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ACL_SLOT =
        keccak256(abi.encode(uint256(keccak256("cofhe.storage.ACL")) - 1)) & ~bytes32(uint256(0xff));

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() MockPermissioned() {}

    function exists() public pure returns (bool) {
        return true;
    }

    /// @dev Auto-registers the requester as handle owner on first call.
    function allow(uint256 handle, address account, address requester) public virtual {
        if (!isAllowed(handle, requester)) {
            ACLStorage storage $ = _getACLStorage();
            $.persistedAllowedPairs[handle][requester] = true;
        }

        ACLStorage storage $ = _getACLStorage();
        $.persistedAllowedPairs[handle][account] = true;
    }

    function allowGlobal(uint256 handle, address requester) public virtual {
        if (msg.sender != TASK_MANAGER_ADDRESS_) {
            revert DirectAllowForbidden(msg.sender);
        }
        if (!isAllowed(handle, requester)) {
            revert SenderNotAllowed(requester);
        }
        ACLStorage storage $ = _getACLStorage();
        $.globalHandles[handle] = true;
    }

    function allowForDecryption(uint256[] memory handlesList, address requester) public virtual {
        if (msg.sender != TASK_MANAGER_ADDRESS_) {
            revert DirectAllowForbidden(msg.sender);
        }
        uint256 len = handlesList.length;
        ACLStorage storage $ = _getACLStorage();
        for (uint256 k = 0; k < len; k++) {
            uint256 handle = handlesList[k];
            if (!isAllowed(handle, requester)) {
                revert SenderNotAllowed(requester);
            }
            $.allowedForDecryption[handle] = true;
        }
        emit AllowedForDecryption(handlesList);
    }

    function allowTransient(uint256 handle, address account, address requester) public virtual {
        if (msg.sender != TASK_MANAGER_ADDRESS_) {
            revert DirectAllowForbidden(msg.sender);
        }
        if (!isAllowed(handle, requester) && requester != TASK_MANAGER_ADDRESS_) {
            revert SenderNotAllowed(requester);
        }
        bytes32 key = keccak256(abi.encodePacked(handle, account));
        assembly {
            // solc-ignore-next-line transient-storage
            tstore(key, 1)
            let length := tload(0)
            let lengthPlusOne := add(length, 1)
            // solc-ignore-next-line transient-storage
            tstore(lengthPlusOne, key)
            // solc-ignore-next-line transient-storage
            tstore(0, lengthPlusOne)
        }
    }

    function delegateAccount(address delegatee, address delegateeContract) public virtual {
        if (msg.sender != TASK_MANAGER_ADDRESS_) {
            revert DirectAllowForbidden(msg.sender);
        }
        if (delegateeContract == msg.sender) {
            revert SenderCannotBeDelegateeAddress();
        }
        ACLStorage storage $ = _getACLStorage();
        if ($.delegates[msg.sender][delegatee][delegateeContract]) {
            revert AlreadyDelegated();
        }
        $.delegates[msg.sender][delegatee][delegateeContract] = true;
        emit NewDelegation(msg.sender, delegatee, delegateeContract);
    }

    function allowedOnBehalf(address delegatee, uint256 handle, address contractAddress, address account)
        public
        view
        virtual
        returns (bool)
    {
        ACLStorage storage $ = _getACLStorage();
        return $.persistedAllowedPairs[handle][account] && $.persistedAllowedPairs[handle][contractAddress]
            && $.delegates[account][delegatee][contractAddress];
    }

    function allowedTransient(uint256 handle, address account) public view virtual returns (bool) {
        bool isAllowedTransient;
        bytes32 key = keccak256(abi.encodePacked(handle, account));
        assembly {
            isAllowedTransient := tload(key)
        }
        return isAllowedTransient;
    }

    function getTaskManagerAddress() public view virtual returns (address) {
        return TASK_MANAGER_ADDRESS_;
    }

    function isAllowed(uint256 handle, address account) public view virtual returns (bool) {
        return allowedTransient(handle, account) || persistAllowed(handle, account) || globalAllowed(handle);
    }

    function isAllowedForDecryption(uint256 handle) public view virtual returns (bool) {
        ACLStorage storage $ = _getACLStorage();
        return $.allowedForDecryption[handle];
    }

    function persistAllowed(uint256 handle, address account) public view virtual returns (bool) {
        ACLStorage storage $ = _getACLStorage();
        return $.persistedAllowedPairs[handle][account];
    }

    function globalAllowed(uint256 handle) public view virtual returns (bool) {
        ACLStorage storage $ = _getACLStorage();
        return $.globalHandles[handle];
    }

    function cleanTransientStorage() external virtual {
        if (msg.sender != TASK_MANAGER_ADDRESS_) {
            revert DirectAllowForbidden(msg.sender);
        }
        assembly {
            let length := tload(0)
            tstore(0, 0)
            let lengthPlusOne := add(length, 1)
            for {
                let i := 1
            } lt(i, lengthPlusOne) {
                i := add(i, 1)
            } {
                let handle := tload(i)
                tstore(i, 0)
                tstore(handle, 0)
            }
        }
    }

    function getVersion() external pure virtual returns (string memory) {
        return string(
            abi.encodePacked(
                CONTRACT_NAME,
                " v",
                Strings.toString(MAJOR_VERSION),
                ".",
                Strings.toString(MINOR_VERSION),
                ".",
                Strings.toString(PATCH_VERSION)
            )
        );
    }

    function _getACLStorage() internal pure returns (ACLStorage storage $) {
        bytes32 slot = ACL_SLOT;
        assembly {
            $.slot := slot
        }
    }

    function isAllowedWithPermission(Permission memory permission, uint256 handle) public view returns (bool) {
        if ((handle & 0x80) == 0x80) return true; // skip byte randomness like isTriviallyEncryptedFromHash()
        return isAllowed(handle, permission.issuer);
    }

    /// @notice Always returns true in dev — same reason as above.
    function checkPermitValidity(Permission memory permission) public view returns (bool) {
        return true;
    }
}
