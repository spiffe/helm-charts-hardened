#!/usr/bin/env bash

set -xe

SCRIPT="$(readlink -f "$0")"
SCRIPTPATH="$(dirname "${SCRIPT}")"
TESTDIR="${SCRIPTPATH}/../../.github/tests"

# shellcheck source=/dev/null
source "${TESTDIR}/common.sh"

"${SCRIPTPATH}/../../.github/scripts/prepare-local-chart-deps.sh"

ns=spire-server

CLEANUP=1

for i in "$@"; do
  case $i in
    -c)
      CLEANUP=0
      shift # past argument=value
      ;;
  esac
done

teardown() {
  print_helm_releases
  print_spire_workload_status "${ns}"

  if [[ "$1" -ne 0 ]]; then
    get_namespace_details "${ns}" default
  fi

  if [ "${CLEANUP}" -eq 1 ]; then
    kubectl delete pod standalone-cm-client --namespace default --ignore-not-found
    helm uninstall --namespace "${ns}" spire 2>/dev/null || true
    kubectl delete ns "${ns}" 2>/dev/null || true
  fi
}

trap 'EC=$? && trap - SIGTERM && teardown $EC' SIGINT SIGTERM EXIT

kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install --namespace "${ns}" \
  --values "${SCRIPTPATH}/values.yaml" \
  --wait spire charts/spire

# The controller manager running in "standalone" deploymentMode is a
# separate Deployment from spire-server; wait for its own rollout too
# (helm --wait only follows the chart's built-in workloads it knows about).
kubectl rollout status --watch --timeout 5m --namespace "${ns}" deployment spire-controller-manager-standalone

helm test --namespace "${ns}" spire

# Validate that a plain workload elsewhere in the cluster (not the
# controller manager's own bootstrap identity) is still issued a SPIFFE ID,
# proving the standalone controller manager Deployment is reconciling the
# "default" ClusterSPIFFEID over its TCP connection to spire-server.
kubectl apply --namespace default -f "${SCRIPTPATH}/client-pod.yaml"
kubectl wait --for=condition=Ready pod/standalone-cm-client --namespace default --timeout 5m

count=30
until kubectl logs standalone-cm-client --namespace default | grep -q 'SPIFFE ID:'; do
  count=$((count - 1))
  if [ "${count}" -le 0 ]; then
    echo "timed out waiting for standalone-cm-client to receive an SVID" >&2
    kubectl logs standalone-cm-client --namespace default
    exit 1
  fi
  sleep 2
done

kubectl logs standalone-cm-client --namespace default
