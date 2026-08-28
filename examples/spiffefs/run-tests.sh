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
  # Undo the selector that ordering 2 uses to take spiffefs down, so a failure
  # mid-phase does not leave the daemonset scaled away.
  kubectl patch daemonset spire-spiffefs -n spire-system --type=strategic \
    -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}' 2>/dev/null || true

  print_helm_releases
  print_spire_workload_status spire-server spire-system

  if [[ "$1" -ne 0 ]]; then
    get_namespace_details spire-server
    get_namespace_details spire-system
    kubectl describe pod spiffefs-test spiffefs-test-late || true
    kubectl describe daemonset/spire-spiffefs -n spire-system || true
    # Bounded: an unbounded dump overflows the step summary size limit.
    for p in $(kubectl get pod -n spire-system -l app.kubernetes.io/name=spiffefs -o name 2>/dev/null); do
      echo "--- ${p} ---"
      kubectl logs -n spire-system "${p}" --prefix --all-containers=true --tail=50 || true
    done
    kubectl logs daemonset/spire-spiffefs-csi-driver -n spire-system --prefix --all-containers=true --tail=30 || true
  fi

  if [ "${CLEANUP}" -eq 1 ]; then
    kubectl delete pod spiffefs-test spiffefs-test-late --ignore-not-found 2>/dev/null || true
    helm uninstall --namespace spire-server spire 2>/dev/null || true
    kubectl delete ns spire-server 2>/dev/null || true
    kubectl delete ns spire-system 2>/dev/null || true
  fi
}

trap 'EC=$? && trap - SIGTERM && teardown $EC' SIGINT SIGTERM EXIT

# The peer group ids are the point here. If the workload's mount shares a peer
# group with the node's, a remount at the source should reach it; if it does not,
# the workload is holding a detached copy of the old filesystem.

pod_node() {
  kubectl get pod "$1" -o go-template='{{ .spec.nodeName }}' 2>/dev/null
}

# The spiffefs pod on a given node. Resolved on each call because a rollout
# replaces it, and a name captured earlier goes stale exactly when the
# post-restart evidence is needed.
node_spiffefs_pod() {
  kubectl get pod -n spire-system -l app.kubernetes.io/name=spiffefs \
    --field-selector "spec.nodeName=$1" -o name 2>/dev/null | head -n 1
}

dump_mount_topology() {
  local pod node sfs
  pod="$1"
  node="$(pod_node "${pod}")"
  sfs="$(node_spiffefs_pod "${node}")"
  echo "=== mount topology for ${pod} ${2} ==="
  echo "--- node ${node:-unknown} via ${sfs:-none} ---"
  if [ -n "${sfs}" ]; then
    kubectl exec -n spire-system "${sfs}" -- \
      sh -c 'grep spiffefs /proc/1/mountinfo || echo "the node has no spiffefs mount"' || true
  else
    echo "no spiffefs pod on ${node:-unknown}"
  fi
  echo "--- workload ---"
  kubectl exec "${pod}" -- \
    sh -c 'grep spiffe /proc/self/mountinfo || echo "the workload has no spiffe mount"' || true
}

# An svid reaches the mount only once the controller manager has created the
# entry, the server has propagated it and the agent has it cached. Poll for it
# rather than racing that pipeline.
wait_for_svid() {
  local pod="$1"
  local when="${2:-}"
  local timeout=120
  local count=0
  while [ "${count}" -lt "${timeout}" ]; do
    if kubectl exec "${pod}" -- test -f /spiffe/private/credential-bundle.private-key.x509.pem 2>/dev/null; then
      return 0
    fi
    sleep 3
    count=$((count + 3))
  done
  echo "No svid appeared in ${pod}'s mount within ${timeout}s."
  dump_mount_topology "${pod}" "${when:-at failure}"
  kubectl exec "${pod}" -- ls -la /spiffe/ /spiffe/private/ || true
  kubectl exec "${pod}" -- cat /spiffe/private/hints.json || true
  kubectl logs -n spire-system "$(node_spiffefs_pod "$(pod_node "${pod}")")" --tail=50 || true
  return 1
}

check_mount() {
  local pod="$1"
  kubectl exec "${pod}" -- ls -l /spiffe/ /spiffe/private/
  kubectl exec "${pod}" -- cat /spiffe/private/hints.json
  # An SVID is one file holding the key and its chain.
  kubectl exec "${pod}" -- grep -q "BEGIN PRIVATE KEY" /spiffe/private/credential-bundle.private-key.x509.pem
  kubectl exec "${pod}" -- grep -q "BEGIN CERTIFICATE" /spiffe/private/credential-bundle.private-key.x509.pem
  # Trust bundle is named for the trust domain from common_test_your_values.
  kubectl exec "${pod}" -- grep -q "BEGIN CERTIFICATE" /spiffe/private/production.other.spiffe-trust-bundle.x509.pem
  # hints.json describes the SVIDs present.
  kubectl exec "${pod}" -- grep -q '"fingerprint"' /spiffe/private/hints.json
}

# Take spiffefs off every node by giving it a nodeSelector nothing matches, and
# put it back by removing that selector.
spiffefs_down() {
  kubectl patch daemonset spire-spiffefs -n spire-system --type=strategic \
    -p '{"spec":{"template":{"spec":{"nodeSelector":{"spiffefs.test/absent":"true"}}}}}'
  local count=0
  while [ "${count}" -lt 120 ]; do
    if [ -z "$(kubectl get pod -n spire-system -l app.kubernetes.io/name=spiffefs -o name)" ]; then
      return 0
    fi
    sleep 3
    count=$((count + 3))
  done
  echo "spiffefs pods did not go away"
  return 1
}

spiffefs_up() {
  kubectl patch daemonset spire-spiffefs -n spire-system --type=strategic \
    -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}'
  kubectl rollout status daemonset/spire-spiffefs -n spire-system --timeout 3m
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
if ! kubectl exec -n spire-system "${SPIFFEFS_POD}" -- ls -la /run/spire/k8s/spiffefs/private; then
  echo "spiffefs has not mounted its filesystem; the failure is in spiffefs itself, not mount propagation."
  exit 1
fi
if ! kubectl exec -n spire-system "${SPIFFEFS_POD}" -- cat /run/spire/k8s/spiffefs/private/hints.json; then
  echo "spiffefs mounted but is not serving hints.json."
  exit 1
fi

kubectl apply -f "${SCRIPTPATH}/test-pod.yaml"
kubectl wait --for=condition=Ready pod/spiffefs-test --timeout 2m

# Hop 2: the mount reached the workload through the CSI driver. An empty
# listing means a bind mount of the bare directory; a permission error means
# spiffefs is refusing the caller.
kubectl exec spiffefs-test -- sh -c 'grep spiffe /proc/self/mounts || echo "no spiffe mount visible to the workload"'
kubectl exec spiffefs-test -- ls -la /spiffe/ /spiffe/private/ || {
  echo "spiffefs mounted on the host but the workload cannot read it: mount propagation is not reaching the pod."
  exit 1
}

echo "spiffefs-test is on $(pod_node spiffefs-test), served by $(node_spiffefs_pod "$(pod_node spiffefs-test)")"

# Ordering 1: spiffefs was already mounted when this workload was published, so
# the csi driver had to carry an existing mount across at bind time. A plain
# bind drops it; only a recursive one picks it up.
wait_for_svid spiffefs-test "on first publish, spiffefs already up"
check_mount spiffefs-test
echo "ordering 1 ok: a workload published after spiffefs was already mounted sees the filesystem."

# Ordering 2: publish a workload while spiffefs is absent, then bring spiffefs
# back. Here nothing exists to carry across at bind time and the mount has to
# arrive by propagation afterwards.
spiffefs_down
sed 's/name: spiffefs-test$/name: spiffefs-test-late/' "${SCRIPTPATH}/test-pod.yaml" | kubectl apply -f -
kubectl wait --for=condition=Ready pod/spiffefs-test-late --timeout 2m

# Nothing should be there yet; if it is, the ordering under test never happened.
if kubectl exec spiffefs-test-late -- test -f /spiffe/private/credential-bundle.private-key.x509.pem 2>/dev/null; then
  echo "spiffefs was supposed to be down, but the workload already has credentials; ordering 2 is not being exercised."
  exit 1
fi

spiffefs_up
wait_for_svid spiffefs-test-late "after spiffefs came up under an existing workload"
check_mount spiffefs-test-late
echo "ordering 2 ok: a workload published before spiffefs picks the filesystem up when it arrives."

# The first workload must still be fine after all that.
check_mount spiffefs-test

# Recorded so a silent restart cannot be mistaken for a surviving mount.
POD_UID="$(kubectl get pod spiffefs-test -o go-template='{{ .metadata.uid }}')"
RESTARTS_BEFORE="$(kubectl get pod spiffefs-test -o go-template='{{ (index .status.containerStatuses 0).restartCount }}')"

dump_mount_topology spiffefs-test "before the restart"

# Restart spiffefs, remounting its filesystem under the running test pod.
kubectl rollout restart daemonset/spire-spiffefs -n spire-system
kubectl rollout status daemonset/spire-spiffefs -n spire-system --timeout 3m

# Let the remount propagate host -> csi driver -> pod before asserting on it.
sleep 15

kubectl get pods -A

wait_for_svid spiffefs-test "after the rollout restart"

# Still works, with the test pod untouched. Wrong propagation would leave it
# holding a stale mount and these reads would fail.
check_mount spiffefs-test

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

# A rollout replaces the pod. A crash does not: kubelet restarts the container in
# place. Kill the process on every node to cover that path too.
SPIFFEFS_RESTARTS_BEFORE="$(kubectl get pod -n spire-system -l app.kubernetes.io/name=spiffefs \
  -o go-template='{{ range .items }}{{ .metadata.name }}={{ (index .status.containerStatuses 0).restartCount }} {{ end }}')"
echo "spiffefs restart counts before: ${SPIFFEFS_RESTARTS_BEFORE}"

for p in $(kubectl get pod -n spire-system -l app.kubernetes.io/name=spiffefs -o name); do
  echo "killing spiffefs in ${p}"
  # hostPID is on, so target the binary rather than pid 1, which is the node's
  # init. The bracket keeps pgrep from matching the shell running it.
  # shellcheck disable=SC2016  # the subshell has to run in the remote shell
  kubectl exec -n spire-system "${p}" -- sh -c 'kill $(pgrep -f "[/]usr/bin/spiffefs")' || true
done

sleep 10
kubectl wait --for=condition=Ready pod -n spire-system -l app.kubernetes.io/name=spiffefs --timeout 2m

SPIFFEFS_RESTARTS_AFTER="$(kubectl get pod -n spire-system -l app.kubernetes.io/name=spiffefs \
  -o go-template='{{ range .items }}{{ .metadata.name }}={{ (index .status.containerStatuses 0).restartCount }} {{ end }}')"
echo "spiffefs restart counts after: ${SPIFFEFS_RESTARTS_AFTER}"

if [ "${SPIFFEFS_RESTARTS_BEFORE}" = "${SPIFFEFS_RESTARTS_AFTER}" ]; then
  echo "No spiffefs container restarted, so this did not exercise an in place restart."
  exit 1
fi

wait_for_svid spiffefs-test "after the in place restart"
check_mount spiffefs-test

POD_UID_FINAL="$(kubectl get pod spiffefs-test -o go-template='{{ .metadata.uid }}')"
RESTARTS_FINAL="$(kubectl get pod spiffefs-test -o go-template='{{ (index .status.containerStatuses 0).restartCount }}')"

if [ "${POD_UID}" != "${POD_UID_FINAL}" ] || [ "${RESTARTS_BEFORE}" != "${RESTARTS_FINAL}" ]; then
  echo "The test pod was restarted or replaced; the mount surviving proves nothing."
  exit 1
fi

echo "spiffefs mount survived an in place container restart with the workload pod untouched."
