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
  if [ "${CLEANUP}" -eq 1 ]; then
    helm uninstall --namespace spire-server spire 2>/dev/null || true
    kubectl delete ns spire-server 2>/dev/null || true
    kubectl delete ns spire-system 2>/dev/null || true

    helm uninstall --namespace mysql spire-root-server 2>/dev/null || true
    kubectl delete ns spire-root-server 2>/dev/null || true
  fi
}

trap 'trap - SIGTERM && teardown' SIGINT SIGTERM EXIT

kubectl create namespace spire-system --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace spire-system pod-security.kubernetes.io/enforce=privileged || true
kubectl create namespace spire-server --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace spire-server pod-security.kubernetes.io/enforce=restricted || true

helm upgrade --install --create-namespace spire charts/spire \
  --namespace spire-root-server \
  --values "${DEPS}/spire-root-server-values.yaml" \
  --wait

kubectl get nodes -o go-template='{{range .items}}{{printf "%s\n" .metadata.uid}}{{end}}' | while read -r line; do
  kubectl exec -t spire-server-0 -n "spire-root-server" -- spire-server entry create -spiffeID spiffe://production.other/production/nested-spire -parentID "spiffe://production.other/spire/agent/k8s_psat/production/$line" -selector k8s:pod-label:app.kubernetes.io/name:server -downstream
done

helm upgrade --install --create-namespace --namespace spire-server --values "${SCRIPTPATH}/values.yaml,${SCRIPTPATH}/../production/values.yaml,${SCRIPTPATH}/../production/values-node-pod-antiaffinity.yaml,${SCRIPTPATH}/../production/example-your-values.yaml" \
  --wait spire charts/spire
helm test --namespace spire-server spire

print_helm_releases
print_spire_workload_status spire-root-server
print_spire_workload_status spire-server
print_spire_workload_status spire-system

if [[ "$1" -ne 0 ]]; then
  get_namespace_details spire-root-server
  get_namespace_details spire-server
  get_namespace_details spire-system
fi
