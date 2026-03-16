#!/bin/bash

set -euo pipefail

# Create allocator wallet
ALLOCATOR_WALLET=$(docker exec -ti lotus lotus wallet new | tr -d '\r')
echo "Allocator Wallet: $ALLOCATOR_WALLET"

# Send funds to allocator wallet
docker exec -ti lotus lotus send "$ALLOCATOR_WALLET" 10000

# Import wallet keys
KEY_FILES=( $(ls docker/devnet/data/lotus/*.keyinfo | xargs -n 1 basename) )

for KEY_FILE in "${KEY_FILES[@]}"; do
    docker exec -ti lotus lotus wallet import "/var/lib/lotus/$KEY_FILE" || echo "Failed to import $KEY_FILE, skipping..."
done

# Add verifier
docker exec -i lotus lotus-shed verifreg add-verifier t0100 "$ALLOCATOR_WALLET" 99999999999

# Approve multisig transaction
# docker exec -i lotus lotus msig approve --from t0101 f080 0

# Retrieve the highest transaction ID from the multisig wallet
# LATEST_TX_ID=$(docker exec -i lotus lotus msig inspect f080 | grep -oP 'ID\s+(\d+)' | awk '{print $2}' | sort -nr | head -n1)
# LATEST_TX_ID=$(docker exec -i lotus lotus msig inspect f080 | awk '/ID/ {print $2}' | sort -nr | head -n1)
LATEST_TX_ID=$(docker exec -i lotus lotus msig inspect f080 | awk '/^Transactions:/{flag=1; next} flag && /^[0-9]+/{print $1}' | sort -nr | head -n1)

# Approve the latest multisig transaction
if [ -n "$LATEST_TX_ID" ]; then
    echo "Approving transaction ID: $LATEST_TX_ID"
    docker exec -i lotus lotus msig approve --from t0101 f080 "$LATEST_TX_ID"
else
    echo "No pending transactions to approve."
fi


# List notaries
NOTARIES=$(docker exec -i lotus lotus filplus list-notaries)
echo "Notaries List:"
echo "$NOTARIES"

# Create client wallet
CLIENT_WALLET=$(docker exec -ti lotus lotus wallet new | tr -d '\r')
echo "Client Wallet: $CLIENT_WALLET"

# Grant datacap
docker exec -ti lotus lotus filplus grant-datacap --from "$ALLOCATOR_WALLET" "$CLIENT_WALLET" 999999999
