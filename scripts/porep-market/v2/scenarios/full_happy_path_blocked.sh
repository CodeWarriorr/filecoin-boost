#!/bin/bash
set -euo pipefail

cat >&2 <<'MSG'
V2 full happy path is intentionally blocked at the current contract boundary.

Live PoRep Market main has DataCapEvidenceAdapter.submitEvidenceBatch(), but
activateEvidence(), refreshEvidenceStatus(), and currentEvidenceStatus() still
return dummy zero decisions/statuses and are marked "will be implemented in the
future".

Run scripts/porep-market/v2/scenarios/proposal_smoke.sh for the implemented V2
boundary: provider registration, DealRequest proposal, DataCapEvidenceAdapter
selection, validator creation, prepared rail, and ACCEPTED state 20.
MSG

exit 2
