// SPDX-License-Identifier: MIT
pragma solidity =0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {DataCapTypes} from "filecoin-solidity/v0.8/types/DataCapTypes.sol";
import {FilAddresses} from "filecoin-solidity/v0.8/utils/FilAddresses.sol";
import {BigInts} from "filecoin-solidity/v0.8/utils/BigInts.sol";
import {CBOR} from "solidity-cborutils/contracts/CBOR.sol";
import {FilecoinCBOR} from "filecoin-solidity/v0.8/cbor/FilecoinCbor.sol";
import {Client} from "src/Client.sol";

/// @notice Forge script that computes ABI-encoded calldata for Client.transfer().
/// Usage:
///   PROVIDER=1000 PIECE_SIZE=2048 DEAL_ID=1 \
///     forge script script/ComputeTransferCalldata.s.sol --rpc-url $RPC_URL -vvvv 2>&1 | grep CALLDATA
///
/// Then call: cast send $CLIENT_CONTRACT --data $CALLDATA --rpc-url $RPC_URL --private-key $KEY
contract ComputeTransferCalldata is Script {
    function run() external view {
        uint64 provider = uint64(vm.envOr("PROVIDER", uint256(1000)));
        uint64 pieceSize = uint64(vm.envOr("PIECE_SIZE", uint256(2048)));
        uint256 dealId = vm.envOr("DEAL_ID", uint256(1));
        bool dealCompleted = vm.envOr("DEAL_COMPLETED", true);

        // PIECE_CID_HEX: raw CIDv1 bytes for the piece. Defaults to the devnet sample CAR CommP.
        bytes memory pieceCid = vm.envOr(
            "PIECE_CID_HEX",
            hex"0181e203922020ab68b07850bae544b4e720ff59fdc7de709a8b5a8e83d6b7ab3ac2fa83e8461b"
        );

        bytes memory operatorData = _buildOperatorData(provider, pieceCid, pieceSize, 518400, 5256000, 100000);

        DataCapTypes.TransferParams memory params = DataCapTypes.TransferParams({
            to: FilAddresses.fromActorID(6),
            amount: BigInts.fromUint256(uint256(pieceSize) * 1 ether),
            operator_data: operatorData
        });

        bytes memory callData = abi.encodeCall(Client.transfer, (params, dealId, dealCompleted));

        console.log("CALLDATA=%s", vm.toString(callData));
        console.log("OPERATOR_DATA=%s", vm.toString(operatorData));
    }

    function _buildOperatorData(
        uint64 provider,
        bytes memory pieceCid,
        uint64 size,
        int64 termMin,
        int64 termMax,
        int64 expiration
    ) internal pure returns (bytes memory) {
        CBOR.CBORBuffer memory buf = CBOR.create(128);
        CBOR.startFixedArray(buf, 2);
        CBOR.startFixedArray(buf, 1);
        CBOR.startFixedArray(buf, 6);
        CBOR.writeUInt64(buf, provider);
        FilecoinCBOR.writeCid(buf, pieceCid);
        CBOR.writeUInt64(buf, size);
        CBOR.writeInt64(buf, termMin);
        CBOR.writeInt64(buf, termMax);
        CBOR.writeInt64(buf, expiration);
        CBOR.startFixedArray(buf, 0);
        return CBOR.data(buf);
    }
}
