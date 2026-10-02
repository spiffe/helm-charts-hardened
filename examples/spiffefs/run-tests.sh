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
    # Bounded so a wedged unmount cannot hang the job. A namespace left
    # Terminating goes away with the cluster.
    kubectl delete pod spiffefs-test --ignore-not-found --timeout=2m 2>/dev/null || true
    kubectl delete -f "${SCRIPTPATH}/test-pod-late.yaml" --ignore-not-found --timeout=2m 2>/dev/null || true
    helm uninstall --namespace spire-server spire --timeout 2m 2>/dev/null || true
    kubectl delete ns spire-server --timeout=2m 2>/dev/null || true
    kubectl delete ns spire-system --timeout=2m 2>/dev/null || true
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
  echo "--- spiffefs csi driver on ${node:-unknown} ---"
  csi_mountinfo "${node}" | grep -E ' /spire-agent-socket|kubernetes.io~csi/spiffefs/' ||
    echo "no spiffefs csi driver mount table on ${node:-unknown}"
  echo "--- workload ---"
  kubectl exec "${pod}" -- \
    sh -c 'grep spiffe /proc/self/mountinfo || echo "the workload has no spiffe mount"' || true
}

# An svid reaches the mount only once the controller manager has created the
# entry, the server has propagated it and the agent has it cached. Poll for it
# rather than racing that pipeline.
#
# Wait for the trust bundle as well as the credential bundle. They arrive by
# different routes: svids come from a per-pid subscription made on demand, while
# trust bundles come from a stream that backs off and retries, so after a restart
# the credentials can land first and the trust bundle follow.
wait_for_svid() {
  local pod="$1"
  local when="${2:-}"
  local timeout=120
  local count=0
  while [ "${count}" -lt "${timeout}" ]; do
    if kubectl exec "${pod}" -- sh -c 'test -f /spiffe/private/credential-bundle.private-key.x509.pem &&
                                       test -f /spiffe/private/production.other.spiffe-trust-bundle.x509.pem' 2>/dev/null; then
      return 0
    fi
    sleep 3
    count=$((count + 3))
  done
  echo "${pod} did not get both a credential bundle and a trust bundle within ${timeout}s."
  dump_mount_topology "${pod}" "${when:-at failure}"
  kubectl exec "${pod}" -- ls -la /spiffe/ /spiffe/private/ || true
  pod_read "${pod}" /spiffe/private/hints.json || true
  kubectl logs -n spire-system "$(node_spiffefs_pod "$(pod_node "${pod}")")" --tail=50 || true
  return 1
}

# Pull a file out of a workload. busybox cat splices to stdout, and that has
# come back empty through kubectl exec; dd does a plain read/write.
pod_read() {
  kubectl exec "$1" -- dd "if=$2" bs=64k 2>/dev/null
}

# Every read path has to return the whole file. Piping goes through
# sendfile/splice rather than read, and used to come back empty: the kernel took
# the file to be zero length and the reader saw a clean end of file. The test pod
# runs busybox, whose cat splices, so this is the reader most workloads on an
# alpine base image will use.
check_read_paths() {
  local pod="$1"
  local file="$2"
  local sizes
  # stat, coreutils cat piped, busybox cat piped, dd piped -- all inside the pod
  sizes="$(kubectl exec "${pod}" -- sh -c "
    wc -c < ${file}
    cat ${file} | wc -c
    busybox cat ${file} 2>/dev/null | wc -c || echo skipped
    dd if=${file} bs=64k 2>/dev/null | wc -c")"
  echo "read paths for ${file} in ${pod} (stat/cat|/bbcat|/dd|): $(echo "${sizes}" | tr '\n' ' ')"

  local want
  want="$(echo "${sizes}" | head -1)"
  if [ -z "${want}" ] || [ "${want}" -le 0 ] 2>/dev/null; then
    echo "${pod}: ${file} reports a size of '${want}'"
    return 1
  fi
  local n
  for n in $(echo "${sizes}" | tail -n +2); do
    [ "${n}" = "skipped" ] && continue
    if [ "${n}" != "${want}" ]; then
      echo "${pod}: a read path returned ${n} bytes of ${file}, expected ${want}. Piping is broken."
      return 1
    fi
  done
}

# spiffefs resolves credentials per calling pid, so a mix-up would hand one
# workload another's private key. hints.json is the only thing that says which
# file holds which identity: the order the agent returns svids in is not
# guaranteed, so look the svid up by hint rather than assuming an index.
check_svid() {
  local pod="$1"
  local hint="$2"
  local expected="$3"
  local hints id file bundle want got

  hints="$(pod_read "${pod}" /spiffe/private/hints.json)"
  id="$(printf '%s' "${hints}" | jq -r --arg h "${hint}" '.hints[] | select(.hint == $h) | .id')"
  if [ -z "${id}" ] || [ "${id}" = "null" ]; then
    echo "${pod}: no svid with hint \"${hint}\" in hints.json:"
    printf '%s\n' "${hints}"
    return 1
  fi

  # The first svid is delivered under the unindexed name; the rest carry theirs.
  if [ "${id}" -eq 0 ]; then
    file=/spiffe/private/credential-bundle.private-key.x509.pem
  else
    file="/spiffe/private/${id}.credential-bundle.private-key.x509.pem"
  fi

  bundle="/tmp/${pod}.${hint:-none}.pem"
  pod_read "${pod}" "${file}" > "${bundle}"

  if ! openssl x509 -in "${bundle}" -noout -text | grep -q "URI:${expected}"; then
    echo "${pod}: ${file} carries the wrong identity, expected ${expected}"
    openssl x509 -in "${bundle}" -noout -text | grep -A1 "Subject Alternative Name" || true
    return 1
  fi

  # The fingerprint is a hash of the whole bundle file, so a reader can tell
  # whether the bundle rotated out from under hints.json.
  want="sha256:$(sha256sum "${bundle}" | cut -d' ' -f1)"
  got="$(printf '%s' "${hints}" | jq -r --arg h "${hint}" '.hints[] | select(.hint == $h) | .fingerprint')"
  if [ "${want}" != "${got}" ]; then
    echo "${pod}: hints.json fingerprint ${got} does not describe ${file} (${want})"
    return 1
  fi
}

svid_count() {
  pod_read "$1" /spiffe/private/hints.json | jq '.hints | length'
}

# Poll until the workload has as many svids as expected. Waiting for the first
# file is not enough: each identity is created and propagated on its own, so a
# second one can arrive well after the first.
wait_for_svid_count() {
  local pod="$1"
  local want="$2"
  local timeout=120
  local count=0
  local have=0
  while [ "${count}" -lt "${timeout}" ]; do
    have="$(svid_count "${pod}" 2>/dev/null || echo 0)"
    if [ "${have}" = "${want}" ]; then
      return 0
    fi
    sleep 3
    count=$((count + 3))
  done
  echo "${pod} has ${have} svids, expected ${want}:"
  pod_read "${pod}" /spiffe/private/hints.json || true
  return 1
}

check_mount() {
  local pod="$1"
  kubectl exec "${pod}" -- ls -l /spiffe/ /spiffe/private/
  pod_read "${pod}" /spiffe/private/hints.json
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

# kind nodes are containers on the runner, so a node's own mount table is one
# docker exec away, whether or not spiffefs is running there.
node_mountinfo() {
  docker exec "$1" cat /proc/self/mountinfo
}

# The spiffefs csi driver's own mount table, found by its command line: its image
# has no shell to exec into. The bracket keeps the scan from matching itself.
csi_mountinfo() {
  # shellcheck disable=SC2016  # expanded by the node's shell
  docker exec "$1" sh -c '
    for p in /proc/[0-9]*; do
      if tr "\0" " " < "$p/cmdline" 2>/dev/null | grep -q -- "-plugin-name [s]piffefs.csi.spiffe.io"; then
        cat "$p/mountinfo"
        exit 0
      fi
    done
    exit 1'
}

# The driver refuses to start on a shared socket mount. Record the shape the
# kubelet and container runtime actually gave it: a slave of the node's mount,
# which still receives spiffefs remounting, and nothing that sends unmounts back.
check_csi_socket_mount() {
  local line
  line="$(csi_mountinfo "$1" | awk '$5 == "/spire-agent-socket"')"
  echo "spiffefs csi driver socket mount on $1: ${line}"
  if [ -z "${line}" ] || ! grep -q ' master:' <<<"${line}" || grep -q ' shared:' <<<"${line}"; then
    echo "expected the socket mount on $1 to be a slave (master:) and not shared"
    return 1
  fi
}

# spiffefs's filesystem is still mounted on the node.
assert_node_mount() {
  if ! node_mountinfo "$1" | awk '$5 == "/run/spire/k8s/spiffefs/private" {
      for (i = 7; i <= NF; i++) if ($i == "-") { if ($(i + 1) ~ /^fuse/) found = 1; break }
    } END { exit !found }'; then
    echo "the spiffefs mount is gone from node $1"
    node_mountinfo "$1" | grep spiffefs || true
    return 1
  fi
}

# Nothing is left mounted for a deleted pod's spiffefs volume, or for any pod's
# when no uid is given.
wait_no_leftovers() {
  local node="$1" uid="${2:-}" left="" count=0
  while [ "${count}" -lt 60 ]; do
    left="$(node_mountinfo "${node}" | awk -v uid="${uid}" '$5 ~ ("/pods/" uid ".*/volumes/kubernetes.io~csi/spiffefs/")')"
    [ -z "${left}" ] && return 0
    sleep 3
    count=$((count + 3))
  done
  echo "mounts left behind on ${node}${uid:+ for pod ${uid}}:"
  echo "${left}"
  return 1
}

# Tear one workload down and check that its neighbour, and the node's spiffefs
# mount, are untouched. A delete that cannot unmount never completes, so it is
# bounded.
delete_beside() {
  local gone="$1" survivor="$2" hint="$3" id="$4" uid
  uid="$(kubectl get pod "${gone}" -o go-template='{{ .metadata.uid }}')"
  kubectl delete pod "${gone}" --timeout=2m
  wait_no_leftovers "${NODE}" "${uid}"
  assert_node_mount "${NODE}"
  wait_for_svid "${survivor}" "after ${gone} was torn down beside it"
  check_mount "${survivor}"
  check_svid "${survivor}" "${hint}" "${id}"
}

# Restart spiffefs in place on every node with the given signal, and check the
# test pod reads through it untouched. A rollout replaces the pod; a crash does
# not: kubelet restarts the container, and init containers do not run again.
restart_spiffefs_in_place() {
  local signal="$1" before after p
  before="$(kubectl get pod -n spire-system -l app.kubernetes.io/name=spiffefs \
    -o go-template='{{ range .items }}{{ .metadata.name }}={{ (index .status.containerStatuses 0).restartCount }} {{ end }}')"
  echo "spiffefs restart counts before SIG${signal}: ${before}"

  for p in $(kubectl get pod -n spire-system -l app.kubernetes.io/name=spiffefs -o name); do
    echo "sending SIG${signal} to spiffefs in ${p}"
    # hostPID is on, so target the binary rather than pid 1, which is the node's
    # init. The bracket keeps pgrep from matching the shell running it.
    kubectl exec -n spire-system "${p}" -- sh -c "kill -${signal} \$(pgrep -f '[/]usr/bin/spiffefs')" || true
  done

  sleep 10
  kubectl wait --for=condition=Ready pod -n spire-system -l app.kubernetes.io/name=spiffefs --timeout 2m

  after="$(kubectl get pod -n spire-system -l app.kubernetes.io/name=spiffefs \
    -o go-template='{{ range .items }}{{ .metadata.name }}={{ (index .status.containerStatuses 0).restartCount }} {{ end }}')"
  echo "spiffefs restart counts after SIG${signal}: ${after}"

  if [ "${before}" = "${after}" ]; then
    echo "No spiffefs container restarted, so SIG${signal} did not exercise an in place restart."
    return 1
  fi

  wait_for_svid spiffefs-test "after the SIG${signal} in place restart"
  check_mount spiffefs-test

  if [ "${POD_UID}" != "$(kubectl get pod spiffefs-test -o go-template='{{ .metadata.uid }}')" ] ||
     [ "${RESTARTS_BEFORE}" != "$(kubectl get pod spiffefs-test -o go-template='{{ (index .status.containerStatuses 0).restartCount }}')" ]; then
    echo "The test pod was restarted or replaced; the mount surviving proves nothing."
    return 1
  fi

  check_svid spiffefs-test "default" "spiffe://production.other/ns/default/sa/default"
  echo "spiffefs mount survived a SIG${signal} in place container restart with the workload pod untouched."
}

# A pod mounting a volume of the given driver from the given container list,
# with the given propagation ("unset" leaves it out). Bidirectional is only
# accepted for privileged containers, so it gets one; otherwise field validation
# would reject it before the policy ever sees it.
admission_pod() {
  local field="$1" propagation="$2" driver="${3:-spiffefs.csi.spiffe.io}"
  local prop_line="" priv_line="" app="" volume
  if [ "${propagation}" != "unset" ]; then prop_line="mountPropagation: ${propagation}"; fi
  if [ "${propagation}" = "Bidirectional" ]; then priv_line="securityContext: {privileged: true}"; fi
  if [ "${field}" = "initContainers" ]; then app='containers: [{name: app, image: busybox, command: ["true"]}]'; fi
  if [ "${driver}" = "emptyDir" ]; then
    volume="emptyDir: {}"
  else
    volume="csi: {driver: ${driver}, readOnly: true}"
  fi
  cat <<MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: spiffefs-admission
spec:
  ${app}
  ${field}:
    - name: main
      image: busybox
      command: ["true"]
      ${priv_line}
      volumeMounts:
        - name: vol
          mountPath: /spiffe
          readOnly: true
          ${prop_line}
  volumes:
    - name: vol
      ${volume}
MANIFEST
}

POLICY_MESSAGE="must set mountPropagation: HostToContainer"

expect_rejected() {
  local desc="$1" out
  shift
  if out="$("$@" 2>&1)"; then
    echo "admission: ${desc} was admitted, expected the mount propagation policy to reject it"
    echo "${out}"
    return 1
  fi
  if ! grep -q "${POLICY_MESSAGE}" <<<"${out}"; then
    echo "admission: ${desc} was rejected, but not by the mount propagation policy:"
    echo "${out}"
    return 1
  fi
  echo "admission: ${desc} rejected as expected"
}

expect_admitted() {
  local desc="$1" out
  shift
  if ! out="$("$@" 2>&1)"; then
    echo "admission: ${desc} was rejected, expected it to be admitted:"
    echo "${out}"
    return 1
  fi
  echo "admission: ${desc} admitted as expected"
  ADMITTED="${out}"
}

dry_run() {
  kubectl apply --dry-run=server -o yaml -f - <<<"$1"
}

# A pod that leaves propagation unset is defaulted where the cluster serves
# MutatingAdmissionPolicy, and rejected where it does not.
expect_unset() {
  local desc="$1" manifest="$2"
  if [ "${MUTATING}" -eq 1 ]; then
    expect_admitted "${desc}" dry_run "${manifest}"
    if ! grep -q 'mountPropagation: HostToContainer' <<<"${ADMITTED}"; then
      echo "admission: ${desc} was admitted without being given HostToContainer:"
      echo "${ADMITTED}"
      return 1
    fi
    echo "admission: ${desc} was given HostToContainer"
  else
    expect_rejected "${desc}" dry_run "${manifest}"
  fi
}

# Prints the documents of a multi-document render whose text matches a pattern.
docs_matching() {
  awk -v pat="$1" '
    /^---$/ { if (doc ~ pat) printf "%s---\n", doc; doc = ""; next }
    { doc = doc $0 "\n" }
    END { if (doc ~ pat) printf "%s", doc }'
}

# CI already installed spire-crds into spire-server. The CRDs are cluster
# scoped, so installing a second release of them here would collide.

kubectl create namespace spire-system --dry-run=client -o yaml | kubectl apply -f -
# spiffefs runs privileged, so this namespace cannot be restricted.
kubectl label namespace spire-system pod-security.kubernetes.io/enforce=privileged || true
kubectl create namespace spire-server --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace spire-server pod-security.kubernetes.io/enforce=restricted || true

# Render checks. These need no cluster, so a chart mistake fails here rather
# than as a confusing runtime symptom.
render() {
  helm template spire charts/spire --namespace spire-server \
    --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/values.yaml" "$@"
}

if render --set spiffefs-csi-driver.agentSocketMountPropagation=Bidirectional >/dev/null 2>&1; then
  echo "The chart rendered a Bidirectional socket mount for the spiffefs csi driver, which the driver refuses."
  exit 1
fi

RENDERED="$(render)"

RECURSIVE="$(docs_matching '"-recursive-bind"' <<<"${RENDERED}")"
if [ "$(grep -c '^kind: DaemonSet' <<<"${RECURSIVE}")" -ne 1 ] || ! grep -q '"spiffefs.csi.spiffe.io"' <<<"${RECURSIVE}"; then
  echo "-recursive-bind should be passed to the spiffefs csi driver and no other. Rendered with it:"
  grep -E '^kind:|^  name:|-plugin-name' <<<"${RECURSIVE}" || true
  exit 1
fi

POLICY=spiffefs.csi.spiffe.io-mount-propagation
POLICIES="$(grep -A2 '^kind: ValidatingAdmissionPolicy$' <<<"${RENDERED}" | grep -o 'name: .*-mount-propagation' || true)"
if [ "${POLICIES}" != "name: ${POLICY}" ]; then
  echo "Expected exactly one mount propagation policy, for the spiffefs csi driver, got: ${POLICIES:-none}"
  exit 1
fi
echo "render ok: Bidirectional is refused, -recursive-bind and the policy apply to the spiffefs csi driver only."

helm upgrade --install --namespace spire-server \
  --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/values.yaml" \
  --wait spire charts/spire

kubectl get pods -A

# The policy is type checked in the background once it is created. A warning
# here means an expression is wrong, and its rule would fail every pod it
# matches.
count=0
until [ -n "$(kubectl get validatingadmissionpolicy "${POLICY}" -o jsonpath='{.status.observedGeneration}')" ]; do
  if [ "${count}" -ge 60 ]; then
    echo "${POLICY} was never type checked."
    exit 1
  fi
  sleep 3
  count=$((count + 3))
done
WARNINGS="$(kubectl get validatingadmissionpolicy "${POLICY}" -o jsonpath='{.status.typeChecking.expressionWarnings}')"
if [ -n "${WARNINGS}" ]; then
  echo "${POLICY} has type checking warnings: ${WARNINGS}"
  exit 1
fi

MUTATING=0
if kubectl api-resources --api-group=admissionregistration.k8s.io -o name | grep -q '^mutatingadmissionpolicies' &&
   kubectl get mutatingadmissionpolicy "${POLICY}" >/dev/null 2>&1; then
  MUTATING=1
fi
echo "MutatingAdmissionPolicy in use: ${MUTATING}"

# A new policy takes effect a little after it is created. Wait for a pod it must
# reject, so the matrix below is not racing that.
count=0
until ! dry_run "$(admission_pod containers None)" >/dev/null 2>&1; do
  if [ "${count}" -ge 60 ]; then
    echo "${POLICY} never started rejecting pods."
    exit 1
  fi
  sleep 3
  count=$((count + 3))
done

expect_rejected "a mount with propagation None" dry_run "$(admission_pod containers None)"
expect_rejected "a privileged Bidirectional mount" dry_run "$(admission_pod containers Bidirectional)"
expect_unset "a mount leaving propagation unset" "$(admission_pod containers unset)"
expect_unset "an init container leaving propagation unset" "$(admission_pod initContainers unset)"
expect_admitted "a HostToContainer mount" dry_run "$(admission_pod containers HostToContainer)"
expect_admitted "a pod without a spiffefs volume" dry_run "$(admission_pod containers unset emptyDir)"
echo "admission ok: spiffefs mounts must use HostToContainer, and other pods are not affected."

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
NODE="$(pod_node spiffefs-test)"
check_csi_socket_mount "${NODE}"

# kubectl debug adds containers through a subresource, which must not be a way
# around the policy.
expect_rejected "an ephemeral container leaving propagation unset" \
  kubectl patch pod spiffefs-test --subresource ephemeralcontainers --dry-run=server --type=strategic \
  -p '{"spec":{"ephemeralContainers":[{"name":"debug","image":"busybox","volumeMounts":[{"name":"spiffefs","mountPath":"/spiffe","readOnly":true}]}]}}'

# Ordering 1: spiffefs was already mounted when this workload was published, so
# the csi driver had to carry an existing mount across at bind time. A plain
# bind drops it; only a recursive one picks it up.
wait_for_svid spiffefs-test "on first publish, spiffefs already up"
check_mount spiffefs-test
check_read_paths spiffefs-test /spiffe/private/hints.json
check_read_paths spiffefs-test /spiffe/private/credential-bundle.private-key.x509.pem
echo "ordering 1 ok: a workload published after spiffefs was already mounted sees the filesystem."

# Ordering 2: publish a workload while spiffefs is absent, then bring spiffefs
# back. Here nothing exists to carry across at bind time and the mount has to
# arrive by propagation afterwards.
spiffefs_down
kubectl apply -f "${SCRIPTPATH}/test-pod-late.yaml"
kubectl wait --for=condition=Ready pod/spiffefs-test-late --timeout 2m

# Nothing should be there yet; if it is, the ordering under test never happened.
if kubectl exec spiffefs-test-late -- test -f /spiffe/private/credential-bundle.private-key.x509.pem 2>/dev/null; then
  # spiffefs is down, so nothing should have been delivered at all
  echo "spiffefs was supposed to be down, but the workload already has credentials; ordering 2 is not being exercised."
  exit 1
fi

spiffefs_up

if [ "$(pod_node spiffefs-test-late)" != "${NODE}" ]; then
  echo "spiffefs-test-late is on $(pod_node spiffefs-test-late), not ${NODE}; the teardown checks need both pods on one node."
  exit 1
fi

wait_for_svid spiffefs-test-late "after spiffefs came up under an existing workload"
check_mount spiffefs-test-late
echo "ordering 2 ok: a workload published before spiffefs picks the filesystem up when it arrives."

# The first workload must still be fine after all that. Poll rather than assert:
# its node may not be the one the late pod is on, and each node remounts on its
# own schedule.
wait_for_svid spiffefs-test "after spiffefs cycled under it"
check_mount spiffefs-test

# Each workload gets its own identity. The two pods run under different service
# accounts, so the controller manager issues them different SPIFFE IDs. An
# identity with no explicit hint is named after its ClusterSPIFFEID key, so the
# chart's stock fallback identity arrives as hint "default", while the late pod
# carries the two explicit identities from values.yaml instead.
# The late pod matches a second, hinted ClusterSPIFFEID, so it should end up with
# two svids: the extra one under an indexed file name, named by hints.json.
wait_for_svid_count spiffefs-test 1
wait_for_svid_count spiffefs-test-late 2
kubectl exec spiffefs-test-late -- ls -l /spiffe/private/

check_svid spiffefs-test      "default" "spiffe://production.other/ns/default/sa/default"
check_svid spiffefs-test-late "multi-main" "spiffe://production.other/ns/default/sa/spiffefs-late"
check_svid spiffefs-test-late "extra"   "spiffe://production.other/spiffefs-test/extra"

if [ "$(sha256sum /tmp/spiffefs-test.default.pem | cut -d' ' -f1)" = \
     "$(sha256sum /tmp/spiffefs-test-late.multi-main.pem | cut -d' ' -f1)" ]; then
  echo "Both workloads were handed the same credential bundle; spiffefs is not scoping by caller."
  exit 1
fi

echo "identity ok: each workload gets its own svid, and a second hinted svid lands under its indexed name."

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

check_svid spiffefs-test "default" "spiffe://production.other/ns/default/sa/default"
echo "spiffefs mount survived a daemonset restart with the workload pod untouched."

# A graceful stop unmounts on the way out. A kill leaves a dead mount behind,
# which the restarted container has to clear itself.
restart_spiffefs_in_place TERM
restart_spiffefs_in_place KILL

# The workload's own container restarting, with the pod kept, gets a fresh view
# of the volume from the node's copy.
WORKLOAD_RESTARTS="$(kubectl get pod spiffefs-test -o go-template='{{ (index .status.containerStatuses 0).restartCount }}')"
kubectl exec spiffefs-test -- touch /tmp/exit
count=0
until [ "$(kubectl get pod spiffefs-test -o go-template='{{ (index .status.containerStatuses 0).restartCount }}')" -gt "${WORKLOAD_RESTARTS}" ]; do
  if [ "${count}" -ge 60 ]; then
    echo "spiffefs-test's container did not restart."
    exit 1
  fi
  sleep 3
  count=$((count + 3))
done
kubectl wait --for=condition=Ready pod/spiffefs-test --timeout 2m
wait_for_svid spiffefs-test "after its container restarted in place"
check_mount spiffefs-test
check_svid spiffefs-test "default" "spiffe://production.other/ns/default/sa/default"
echo "a workload container restarted in place still reads spiffefs."

# Tearing a workload down detaches the volume beneath it. That must stop at the
# workload: the neighbour on the same node, and the node's spiffefs mount, stay.
delete_beside spiffefs-test spiffefs-test-late "multi-main" "spiffe://production.other/ns/default/sa/spiffefs-late"
echo "a workload torn down beside another left it, and spiffefs, untouched."

# A restarted csi driver does not bind the volumes it already published: it gets
# them from the container runtime, copied from the node. Teardown through those
# copies has to stop at the workload too.
kubectl apply -f "${SCRIPTPATH}/test-pod.yaml"
kubectl wait --for=condition=Ready pod/spiffefs-test --timeout 2m
if [ "$(pod_node spiffefs-test)" != "${NODE}" ]; then
  echo "spiffefs-test came back on $(pod_node spiffefs-test), not ${NODE}."
  exit 1
fi
wait_for_svid spiffefs-test "after being recreated"

kubectl rollout restart daemonset/spire-spiffefs-csi-driver -n spire-system
kubectl rollout status daemonset/spire-spiffefs-csi-driver -n spire-system --timeout 3m
check_csi_socket_mount "${NODE}"
dump_mount_topology spiffefs-test "after the csi driver restarted"

check_mount spiffefs-test
check_mount spiffefs-test-late
delete_beside spiffefs-test spiffefs-test-late "multi-main" "spiffe://production.other/ns/default/sa/spiffefs-late"
echo "a workload torn down through a restarted csi driver left its neighbour, and spiffefs, untouched."

# With spiffefs down nothing is mounted beneath the volume, so teardown takes
# the plain unmount instead of the detaching one.
spiffefs_down
LATE_UID="$(kubectl get pod spiffefs-test-late -o go-template='{{ .metadata.uid }}')"
kubectl delete pod spiffefs-test-late --timeout=2m
wait_no_leftovers "${NODE}" "${LATE_UID}"
spiffefs_up
assert_node_mount "${NODE}"
echo "a workload torn down while spiffefs was down left nothing behind."

for n in $(kubectl get nodes -o go-template='{{ range .items }}{{ .metadata.name }} {{ end }}'); do
  wait_no_leftovers "${n}"
done
echo "no spiffefs volume mounts are left on any node."
