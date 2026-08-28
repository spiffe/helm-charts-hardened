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
  print_spire_workload_status spire-server spire-system

  if [[ "$1" -ne 0 ]]; then
    get_namespace_details spire-server
    get_namespace_details spire-system
    kubectl describe pod spiffefs-test || true
    kubectl describe daemonset/spire-spiffefs -n spire-system || true
    # Bounded: an unbounded dump overflows the step summary size limit.
    kubectl logs daemonset/spire-spiffefs -n spire-system --prefix --all-containers=true --tail=100 || true
    kubectl logs daemonset/spire-spiffefs-csi-driver -n spire-system --prefix --all-containers=true --tail=30 || true
  fi

  if [ "${CLEANUP}" -eq 1 ]; then
    kubectl delete -f "${SCRIPTPATH}/test-pod.yaml" --ignore-not-found 2>/dev/null || true
    helm uninstall --namespace spire-server spire 2>/dev/null || true
    kubectl delete ns spire-server 2>/dev/null || true
    kubectl delete ns spire-system 2>/dev/null || true
  fi
}

trap 'EC=$? && trap - SIGTERM && teardown $EC' SIGINT SIGTERM EXIT

# Must hold both before and after spiffefs is restarted under the pod.
check_mount() {
  kubectl exec spiffefs-test -- ls -l /spiffe/
  kubectl exec spiffefs-test -- cat /spiffe/hints.json
  # An SVID is one file holding the key and its chain.
  kubectl exec spiffefs-test -- grep -q "BEGIN PRIVATE KEY" /spiffe/credential-bundle.private-key.x509.pem
  kubectl exec spiffefs-test -- grep -q "BEGIN CERTIFICATE" /spiffe/credential-bundle.private-key.x509.pem
  # Trust bundle is named for the trust domain from common_test_your_values.
  kubectl exec spiffefs-test -- grep -q "BEGIN CERTIFICATE" /spiffe/production.other.spiffe-trust-bundle.x509.pem
  # hints.json describes the SVIDs present.
  kubectl exec spiffefs-test -- grep -q '"fingerprint"' /spiffe/hints.json
}

# CI already installed spire-crds into spire-server. The CRDs are cluster
# scoped, so installing a second release of them here would collide.

kubectl create namespace spire-system --dry-run=client -o yaml | kubectl apply -f -
# spiffefs runs privileged, so this namespace cannot be restricted.
kubectl label namespace spire-system pod-security.kubernetes.io/enforce=privileged || true
kubectl create namespace spire-server --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace spire-server pod-security.kubernetes.io/enforce=restricted || true

helm upgrade --install --namespace spire-server \
  --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/values.yaml" \
  --wait spire charts/spire

kubectl get pods -A

# Hop 1: spiffefs mounted its filesystem in its own container. A failure here
# is spiffefs itself (agent socket, /dev/fuse, mount) rather than propagation.
SPIFFEFS_POD="$(kubectl get pod -n spire-system -l app.kubernetes.io/name=spiffefs -o name | head -n 1)"
if [ -z "${SPIFFEFS_POD}" ]; then
  echo "No spiffefs pod found in spire-system."
  exit 1
fi
kubectl logs -n spire-system "${SPIFFEFS_POD}" --tail=50
# A fuse entry here separates "never mounted" from "mounted but erroring".
kubectl exec -n spire-system "${SPIFFEFS_POD}" -- sh -c 'grep spiffefs /proc/self/mounts || echo "no spiffefs mount in this container"'
# hostPID lets us read the node's own mount table through pid 1. If the fuse
# mount is absent here it never propagated out of the spiffefs container, so
# nothing downstream can see it either.
kubectl exec -n spire-system "${SPIFFEFS_POD}" -- sh -c 'grep spiffefs /proc/1/mountinfo || echo "the node does not see the spiffefs mount"'
if ! kubectl exec -n spire-system "${SPIFFEFS_POD}" -- ls -la /run/spire/k8s/spiffefs; then
  echo "spiffefs has not mounted its filesystem; the failure is in spiffefs itself, not mount propagation."
  exit 1
fi
if ! kubectl exec -n spire-system "${SPIFFEFS_POD}" -- cat /run/spire/k8s/spiffefs/hints.json; then
  echo "spiffefs mounted but is not serving hints.json."
  exit 1
fi

kubectl apply -f "${SCRIPTPATH}/test-pod.yaml"
kubectl wait --for=condition=Ready pod/spiffefs-test --timeout 2m

# Hop 2: the mount reached the workload through the CSI driver. An empty
# listing means a bind mount of the bare directory; a permission error means
# spiffefs is refusing the caller.
kubectl exec spiffefs-test -- sh -c 'grep spiffe /proc/self/mounts || echo "no spiffe mount visible to the workload"'
kubectl exec spiffefs-test -- ls -la /spiffe/ || {
  echo "spiffefs mounted on the host but the workload cannot read it: mount propagation is not reaching the pod."
  exit 1
}

# The mount works to begin with.
check_mount

# Recorded so a silent restart cannot be mistaken for a surviving mount.
POD_UID="$(kubectl get pod spiffefs-test -o go-template='{{ .metadata.uid }}')"
RESTARTS_BEFORE="$(kubectl get pod spiffefs-test -o go-template='{{ (index .status.containerStatuses 0).restartCount }}')"

# Restart spiffefs, remounting its filesystem under the running test pod.
kubectl rollout restart daemonset/spire-spiffefs -n spire-system
kubectl rollout status daemonset/spire-spiffefs -n spire-system --timeout 2m

# Let the remount propagate host -> csi driver -> pod before asserting on it.
sleep 15

kubectl get pods -A

# Still works, with the test pod untouched. Wrong propagation would leave it
# holding a stale mount and these reads would fail.
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
