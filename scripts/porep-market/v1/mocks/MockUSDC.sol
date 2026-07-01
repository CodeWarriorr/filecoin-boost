// SPDX-License-Identifier: Apache-2.0 OR MIT
// ──────────────────────────────────────────────────────────────────────
// VENDORED from filecoin-pay  (https://github.com/FilOzone/filecoin-pay)
//   Source : test/mocks/MockERC20.sol
//   Commit : f0a40fe287ecb08c2c20b828bdbadd2437988bba  (FilecoinPay 1.0.0)
//
// Deltas from source:
//   1. Contract renamed  MockERC20 -> MockUSDC
//   2. Added decimals() override returning 6
//      Why: real USDC uses 6 decimals — worst-case scenario for our price
//      math (pricePerSectorPerMonth / EPOCHS_IN_MONTH). Testing with 6
//      decimals catches integer-division precision bugs that 18-decimal
//      tokens would hide.
//   3. Pragma pinned ^0.8.27 -> =0.8.30  (porep-market repo convention)
//   4. IERC3009 import changed from relative path to remapping:
//      ../../src/interfaces/IERC3009.sol -> filecoin-pay/interfaces/IERC3009.sol
// ──────────────────────────────────────────────────────────────────────
pragma solidity =0.8.30;

import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC3009} from "filecoin-pay/interfaces/IERC3009.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20, ERC20Permit, IERC3009 {
    // --- ERC-3009 State and Constants ---
    mapping(address => mapping(bytes32 => bool)) private _authorizationStates;

    bytes32 private constant _TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 private constant _RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    bytes32 private immutable _HASHED_NAME;
    bytes32 private constant _HASHED_VERSION = keccak256("1");

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 private constant _PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _TYPE_HASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    uint256 private immutable _CACHED_CHAIN_ID;
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;

    // --- ERC-3009 Event ---
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

    constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) {
        _HASHED_NAME = keccak256(abi.encode(name));
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION);
    }

    // --- Delta #2: 6 decimals (real USDC) ---
    function decimals() public pure override returns (uint8) { return 6; }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // --- ERC-3009 Implementation ---

    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(block.timestamp > validAfter, "EIP3009: authorization not yet valid");
        require(block.timestamp < validBefore, "EIP3009: authorization expired");
        require(!_authorizationStates[from][nonce], "EIP3009: authorization already used");

        bytes32 structHash = keccak256(
            abi.encode(_TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, v, r, s);
        require(signer == from, "Invalid signature");

        _authorizationStates[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);

        _transfer(from, to, value);
    }

    function receiveWithAuthorization(
        address _from,
        address _to,
        uint256 _value,
        uint256 _validAfter,
        uint256 _validBefore,
        bytes32 _nonce,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        require(_to == msg.sender, "EIP3009: caller must be the recipient");
        require(block.timestamp > _validAfter, "EIP3009: authorization not yet valid");
        require(block.timestamp < _validBefore, "EIP3009: authorization expired");
        require(!_authorizationStates[_from][_nonce], "EIP3009: authorization already used");
        _requireValidRecipient(_to);

        address recoveredAddress = _recover(
            _v,
            _r,
            _s,
            abi.encode(_RECEIVE_WITH_AUTHORIZATION_TYPEHASH, _from, _to, _value, _validAfter, _validBefore, _nonce)
        );
        require(recoveredAddress == _from, "EIP3009: invalid signature");

        _authorizationStates[_from][_nonce] = true;
        emit AuthorizationUsed(_from, _nonce);

        _transfer(_from, _to, _value);
    }

    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
        return _authorizationStates[authorizer][nonce];
    }

    function _requireValidRecipient(address _recipient) internal view {
        require(
            _recipient != address(0) && _recipient != address(this),
            "DebtToken: Cannot transfer tokens directly to the Debt token contract or the zero address"
        );
    }

    function _recover(uint8 _v, bytes32 _r, bytes32 _s, bytes memory _typeHashAndData)
        internal
        view
        returns (address)
    {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator(), keccak256(_typeHashAndData)));
        address recovered = ecrecover(digest, _v, _r, _s);
        require(recovered != address(0), "EIP712: invalid signature");
        return recovered;
    }

    function domainSeparator() public view returns (bytes32) {
        if (block.chainid == _CACHED_CHAIN_ID) {
            return _CACHED_DOMAIN_SEPARATOR;
        } else {
            return _buildDomainSeparator(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION);
        }
    }

    function _buildDomainSeparator(bytes32 _typeHash, bytes32 _name, bytes32 _version) private view returns (bytes32) {
        return keccak256(abi.encode(_typeHash, _name, _version, block.chainid, address(this)));
    }
}
