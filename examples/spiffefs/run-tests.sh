#!/usr/bin/env bash

set -xe

SCRIPT="$(readlink -f "$0")"
SCRIPTPATH="$(dirname "${SCRIPT}")"
TESTDIR="${SCRIPTPATH}/../../.github/tests"

# shellcheck source=/dev/null
source "${SCRIPTPATH}/../../.github/scripts/parse-versions.sh"
# shellcheck source=/dev/null
source "${TESTDIR}/common.sh"

"${SCRIPTPATH}/../../.github/scripts/prepare-local-chart-deps.sh"

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
    kubectl describe pod spiffefs-test || true
    kubectl logs daemonset/spire-spiffefs -n spire-system --prefix --all-containers=true || true
    kubectl logs daemonset/spire-spiffefs-csi-driver -n spire-system --prefix --all-containers=true || true
  fi

  if [ "${CLEANUP}" -eq 1 ]; then
    kubectl delete -f "${SCRIPTPATH}/test-pod.yaml" --ignore-not-found 2>/dev/null || true
    helm uninstall --namespace spire-mgmt spire 2>/dev/null || true
    helm uninstall --namespace spire-mgmt spire-crds 2>/dev/null || true
    kubectl delete ns spire-server 2>/dev/null || true
    kubectl delete ns spire-system 2>/dev/null || true
    kubectl delete ns spire-mgmt 2>/dev/null || true
  fi
}

trap 'EC=$? && trap - SIGTERM && teardown $EC' SIGINT SIGTERM EXIT

# Read the filesystem from inside the running test pod. Every assertion here has
# to hold both before and after spiffefs is restarted underneath the pod.
check_mount() {
  kubectl exec spiffefs-test -- ls -l /spiffe/
  kubectl exec spiffefs-test -- cat /spiffe/hints.json
  # An SVID is delivered as one file holding the key and its chain.
  kubectl exec spiffefs-test -- grep -q "BEGIN PRIVATE KEY" /spiffe/credential-bundle.private-key.x509.pem
  kubectl exec spiffefs-test -- grep -q "BEGIN CERTIFICATE" /spiffe/credential-bundle.private-key.x509.pem
  # The trust bundle is named for the trust domain, set in common_test_your_values.
  kubectl exec spiffefs-test -- grep -q "BEGIN CERTIFICATE" /spiffe/production.other.spiffe-trust-bundle.x509.pem
  # hints.json always exists and always describes the SVIDs actually present.
  kubectl exec spiffefs-test -- grep -q '"fingerprint"' /spiffe/hints.json
}

helm upgrade --install --create-namespace --namespace spire-mgmt spire-crds charts/spire-crds

helm upgrade --install --create-namespace --namespace spire-mgmt \
  --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/values.yaml" \
  --set "global.spire.namespaces.create=true" \
  --wait spire charts/spire

kubectl get pods -A

kubectl apply -f "${SCRIPTPATH}/test-pod.yaml"
kubectl wait --for=condition=Ready pod/spiffefs-test --timeout 5m

# The mount works to begin with.
check_mount

# Remember exactly which pod and which container instance we are talking to, so
# that a silent restart cannot be mistaken for a surviving mount.
POD_UID="$(kubectl get pod spiffefs-test -o go-template='{{ .metadata.uid }}')"
RESTARTS_BEFORE="$(kubectl get pod spiffefs-test -o go-template='{{ (index .status.containerStatuses 0).restartCount }}')"

# Restart spiffefs. Its FUSE filesystem is torn down and remounted underneath
# the still-running test pod.
kubectl rollout restart daemonset/spire-spiffefs -n spire-system
kubectl rollout status daemonset/spire-spiffefs -n spire-system --timeout 5m

# Let the remount propagate host -> csi driver -> pod before asserting on it.
sleep 15

kubectl get pods -A

# The mount still works, without the test pod having been restarted. If mount
# propagation were wrong, the pod would be holding a stale mount and these reads
# would fail.
check_mount

POD_UID_AFTER="$(kubectl get pod spiffefs-test -o go-template='{{ .metadata.uid }}')"
RESTARTS_AFTER="$(kubectl get pod spiffefs-test -o go-template='{{ (index .status.containerStatuses 0).restartCount }}')"

if [ "${POD_UID}" != "${POD_UID_AFTER}" ]; then
  echo "The test pod was replaced (${POD_UID} -> ${POD_UID_AFTER}); the mount surviving proves nothing."
  exit 1
fi

if [ "${RESTARTS_BEFORE}" != "${RESTARTS_AFTER}" ]; then
  echo "The test pod's container restarted (${RESTARTS_BEFORE} -> ${RESTARTS_AFTER}); the mount surviving proves nothing."
  exit 1
fi

echo "spiffefs mount survived a daemonset restart with the workload pod untouched."
