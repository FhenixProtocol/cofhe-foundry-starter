#!/usr/bin/env bash
set -euo pipefail

# Start Anvil with CoFHE mocks etched at hardcoded addresses.
# Afterwards deploy and initialize everything via forge script.

ROOT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANVIL_LOG="${ROOT_DIR}/.anvil.log"

cleanup() {
  if [[ -n "${ANVIL_PID:-}" ]] && kill -0 "${ANVIL_PID}" 2>/dev/null; then
    kill "${ANVIL_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

for cmd in anvil forge cast; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is not installed or not in PATH." >&2
    exit 1
  fi
done

echo "Starting anvil (logs: ${ANVIL_LOG})..."
anvil --host 127.0.0.1 --port 8545 --chain-id 31337 >"${ANVIL_LOG}" 2>&1 &
ANVIL_PID=$!

# Wait for anvil
for _ in {1..20}; do
  if cast rpc eth_chainId --rpc-url http://127.0.0.1:8545 >/dev/null 2>&1; then
    break
  fi
  sleep 0.3
done

# anvil acct #9
DEPLOY_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" # Anvil account #0
RPC="http://127.0.0.1:8545"

cd "${ROOT_DIR}"

echo "Etching CoFHE mocks..."
TM_CODE=$(forge inspect MockTaskManager deployedBytecode)
ACL_CODE=$(forge inspect ForgeMockACL deployedBytecode)
ZK_CODE=$(forge inspect MockZkVerifier deployedBytecode)
TN_CODE=$(forge inspect MockThresholdNetwork deployedBytecode)

cast rpc anvil_setCode 0xeA30c4B8b44078Bbf8a6ef5b9f1eC1626C7848D9 "$TM_CODE" --rpc-url "$RPC" > /dev/null
cast rpc anvil_setCode 0xa6Ea4b5291d044D93b73b3CFf3109A1128663E8B "$ACL_CODE" --rpc-url "$RPC" > /dev/null
cast rpc anvil_setCode 0x0000000000000000000000000000000000005001 "$ZK_CODE" --rpc-url "$RPC" > /dev/null
cast rpc anvil_setCode 0x0000000000000000000000000000000000005002 "$TN_CODE" --rpc-url "$RPC" > /dev/null

echo "Deploying..."
forge script script/DeployDev.s.sol:DeployDev \
  --rpc-url "$RPC" \
  --private-key "${DEPLOY_KEY}" \
  --broadcast

echo ""
echo "Local node running on ${RPC} (PID: ${ANVIL_PID})"
echo "Press Ctrl+C to stop."
wait "${ANVIL_PID}"
