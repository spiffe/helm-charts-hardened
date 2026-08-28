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
    # Keep these bounded. An unbounded dump here overflowed the 1024k step
    # summary limit on a previous run and GitHub discarded the entire log.
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

# The CI harness has already installed spire-crds into the spire-server
# namespace for us. Installing it again from here would collide: the CRDs are
# cluster scoped, so a second release cannot take ownership of them.

kubectl create namespace spire-system --dry-run=client -o yaml | kubectl apply -f -
# spiffefs mounts a FUSE filesystem and runs privileged, so the namespace it
# lands in cannot be at the restricted pod security level.
kubectl label namespace spire-system pod-security.kubernetes.io/enforce=privileged || true
kubectl create namespace spire-server --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace spire-server pod-security.kubernetes.io/enforce=restricted || true

helm upgrade --install --namespace spire-server \
  --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/values.yaml" \
  --wait spire charts/spire

kubectl get pods -A

# Hop 1: spiffefs has actually mounted its filesystem inside its own container.
# If this fails, nothing downstream can work and the problem is spiffefs itself
# (its agent socket, /dev/fuse, or the mount call) rather than propagation.
SPIFFEFS_POD="$(kubectl get pod -n spire-system -l app.kubernetes.io/name=spiffefs -o name | head -n 1)"
if [ -z "${SPIFFEFS_POD}" ]; then
  echo "No spiffefs pod found in spire-system."
  exit 1
fi
kubectl logs -n spire-system "${SPIFFEFS_POD}" --tail=50
# Whether the mount table shows a fuse entry here separates "spiffefs never
# mounted" from "it mounted but the filesystem is erroring".
kubectl exec -n spire-system "${SPIFFEFS_POD}" -- sh -c 'grep spiffefs /proc/self/mounts || echo "no spiffefs mount in this container"'
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

# Hop 2: the mount reached the workload through the CSI driver. Reaching here
# with hop 1 passing means any failure below is a propagation problem. An empty
# listing means the pod holds a bind mount of the bare directory rather than the
# filesystem; a permission error instead means spiffefs is refusing the caller.
kubectl exec spiffefs-test -- sh -c 'grep spiffe /proc/self/mounts || echo "no spiffe mount visible to the workload"'
kubectl exec spiffefs-test -- ls -la /spiffe/ || {
  echo "spiffefs mounted on the host but the workload cannot read it: mount propagation is not reaching the pod."
  exit 1
}

# The mount works to begin with.
check_mount

# Remember exactly which pod and which container instance we are talking to, so
# that a silent restart cannot be mistaken for a surviving mount.
POD_UID="$(kubectl get pod spiffefs-test -o go-template='{{ .metadata.uid }}')"
RESTARTS_BEFORE="$(kubectl get pod spiffefs-test -o go-template='{{ (index .status.containerStatuses 0).restartCount }}')"

# Restart spiffefs. Its FUSE filesystem is torn down and remounted underneath
# the still-running test pod.
kubectl rollout restart daemonset/spire-spiffefs -n spire-system
kubectl rollout status daemonset/spire-spiffefs -n spire-system --timeout 2m

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
