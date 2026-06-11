#!/usr/bin/env bash
# Render besu-sandbox and run Checkov with the chart's .checkov.yaml skips.
# Usage (from repo root): ./scripts/checkov-scan.sh [release-name]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="${ROOT}/charts/besu-sandbox"
RELEASE="${1:-sbx}"
NS="${CHECKOV_NAMESPACE:-besu-checkov}"
OUT="${TMPDIR:-/tmp}/besu-sandbox-checkov"
CONFIG="${CHART}/.checkov.yaml"

mkdir -p "${OUT}"

render() {
  local name="$1"
  shift
  helm template "${RELEASE}" "${CHART}" -n "${NS}" "$@" > "${OUT}/${name}.yaml"
}

echo "Rendering manifests (namespace=${NS})..."
render "default"
render "network-policy" --set networkPolicy.enabled=true

run_checkov() {
  local manifest="$1"
  echo ""
  echo "==> Checkov: $(basename "${manifest}")"
  if command -v checkov >/dev/null 2>&1; then
    checkov -f "${manifest}" \
      --framework kubernetes \
      --config-file "${CONFIG}" \
      --compact
  else
    docker run --rm \
      -v "${manifest}:/manifests.yaml:ro" \
      -v "${CONFIG}:/checkov.yaml:ro" \
      bridgecrew/checkov:latest \
      -f /manifests.yaml \
      --framework kubernetes \
      --config-file /checkov.yaml \
      --compact
  fi
}

run_checkov "${OUT}/default.yaml"
run_checkov "${OUT}/network-policy.yaml"

echo ""
echo "Checkov scan finished successfully."
