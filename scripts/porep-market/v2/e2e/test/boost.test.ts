import test from "node:test";
import assert from "node:assert/strict";
import { assertDirectImportSealingWindowIsSafe, filecoinAddressFromEvmStat } from "../src/devnet/boost.js";

test("filecoinAddressFromEvmStat parses lotus evm stat output", () => {
  assert.equal(
    filecoinAddressFromEvmStat([
      "Filecoin address:  t410ftfxk5ctnldmgdutoyibkmmdv3bnurlacm5ws3eq",
      "Eth address:  0x996eae8a6d58d861d26ec202a63075d85b48ac02",
      "ID address:  t01063"
    ].join("\n")),
    "t410ftfxk5ctnldmgdutoyibkmmdv3bnurlacm5ws3eq"
  );
});

test("direct import sealing precondition rejects default devnet sealing buffers", () => {
  assert.throws(
    () => assertDirectImportSealingWindowIsSafe({
      startEpochOffset: 55,
      boostStartEpochSealingBuffer: 480,
      minerStartEpochSealingBuffer: 480
    }),
    /StartEpochSealingBuffer.*480.*DIRECT_IMPORT_START_EPOCH_OFFSET.*55/
  );
});

test("direct import sealing precondition accepts fast-sealing devnet buffers", () => {
  assert.doesNotThrow(() => assertDirectImportSealingWindowIsSafe({
    startEpochOffset: 55,
    boostStartEpochSealingBuffer: 20,
    minerStartEpochSealingBuffer: 20
  }));
});
