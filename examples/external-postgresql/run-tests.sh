#!/usr/bin/env bash

set -xe

SCRIPT="$(readlink -f "$0")"
SCRIPTPATH="$(dirname "${SCRIPT}")"
TESTDIR="${SCRIPTPATH}/../../.github/tests"
DEPS="${TESTDIR}/dependencies"

# shellcheck source=/dev/null
source "${SCRIPTPATH}/../../.github/scripts/parse-versions.sh"
# shellcheck source=/dev/null
source "${TESTDIR}/common.sh"

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
  print_spire_workload_status spire-server
  print_spire_workload_status spire-system

  if [[ "$1" -ne 0 ]]; then
    get_namespace_details spire-server
    get_namespace_details spire-system
  fi

  if [ "${CLEANUP}" -eq 1 ]; then
    helm uninstall --namespace "spire-server" spire 2>/dev/null || true
    helm uninstall --namespace "spire-server" postgresql 2>/dev/null || true
    kubectl delete ns spire-server 2>/dev/null || true
    kubectl delete ns spire-system 2>/dev/null || true
  fi
}

trap 'EC=$? && trap - SIGTERM && teardown $EC' SIGINT SIGTERM EXIT

kubectl create namespace spire-system --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace spire-system pod-security.kubernetes.io/enforce=privileged || true
kubectl create namespace spire-server --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace spire-server pod-security.kubernetes.io/enforce=restricted || true

helm upgrade --install postgresql postgresql --version "$VERSION_POSTGRESQL" --repo "$HELM_REPO_POSTGRESQL" \
  --namespace spire-server \
  --values "${DEPS}/postgresql.yaml,${SCRIPTPATH}/../production/values.yaml,${SCRIPTPATH}/../production/values-node-pod-antiaffinity.yaml" \
  --wait

helm upgrade --install --namespace "spire-server" \
  --values "${SCRIPTPATH}/values.yaml,${SCRIPTPATH}/../production/values.yaml,${SCRIPTPATH}/../production/values-node-pod-antiaffinity.yaml,${SCRIPTPATH}/../production/example-your-values.yaml" \
  --set 'spire-server.dataStore.sql.password=sp1ff3Test' --wait spire charts/spire
helm test --namespace "spire-server" spire
