#!/usr/bin/env bash

set -euo pipefail

SCRIPT="$(readlink -f "$0")"
SCRIPTPATH="$(dirname "${SCRIPT}")"
REPO_ROOT="$(dirname "${SCRIPTPATH}")/.."

charts=(
  "charts/spiffe-csi-driver"
  "charts/spiffe-oidc-discovery-provider"
  "charts/spike-keeper"
  "charts/spike-nexus"
  "charts/spike-pilot"
  "charts/spire-agent"
  "charts/spire"
  "charts/spire-ha-agent"
  "charts/spire-nested"
  "charts/spire-server"
  "charts/tornjak-frontend"
)

for chart in "${charts[@]}"; do
  chart_path="${REPO_ROOT}/${chart}"
  if grep -q 'file://../spire-lib' "${chart_path}/Chart.yaml"; then
    helm dependency update --skip-refresh "${chart_path}"
  fi
done
