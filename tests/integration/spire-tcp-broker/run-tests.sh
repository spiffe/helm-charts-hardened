#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-chart-testing}"
KUBE_CONTEXT="kind-${KIND_CLUSTER_NAME}"
K8S="${K8S:-}"
DEFAULT_SPIRE_SERVER_IMAGE="ghcr.io/spiffe/spire-server:1.15.1"
DEFAULT_SPIRE_AGENT_IMAGE="ghcr.io/spiffe/spire-agent:1.15.1"

# To test against locally built SPIRE images from a SPIRE checkout:
#   SPIRE_REPO=/path/to/spire
#   SPIRE_TAG=1.15.1
#   docker buildx build --load \
#     --build-arg goversion="$(cat "${SPIRE_REPO}/.go-version")" \
#     --build-arg TAG="${SPIRE_TAG}" \
#     --target spire-server \
#     --tag local/spire-server:spire-tcp-broker-integration \
#     --file "${SPIRE_REPO}/Dockerfile" \
#     "${SPIRE_REPO}"
#   docker buildx build --load \
#     --build-arg goversion="$(cat "${SPIRE_REPO}/.go-version")" \
#     --build-arg TAG="${SPIRE_TAG}" \
#     --target spire-agent \
#     --tag local/spire-agent:spire-tcp-broker-integration \
#     --file "${SPIRE_REPO}/Dockerfile" \
#     "${SPIRE_REPO}"
#
# When both local images exist and SPIRE_SERVER_IMAGE/SPIRE_AGENT_IMAGE are
# unset, the script uses these images automatically.
LOCAL_SPIRE_SERVER_IMAGE="local/spire-server:spire-tcp-broker-integration"
LOCAL_SPIRE_AGENT_IMAGE="local/spire-agent:spire-tcp-broker-integration"
SPIRE_SERVER_IMAGE="${SPIRE_SERVER_IMAGE:-}"
SPIRE_AGENT_IMAGE="${SPIRE_AGENT_IMAGE:-}"
CLIENT_IMAGE="${CLIENT_IMAGE:-local/spire-tcp-broker-client:integration}"

SERVER_NAMESPACE=spire-server
MANAGEMENT_NAMESPACE=spire-mgmt
APP_A_NAMESPACE=broker-app-a
APP_B_NAMESPACE=broker-app-b
BROKER_RELEASE=spire-tcp-broker
CLEANUP=1

usage() {
  cat <<EOF
Usage: $0 [-c] [--skip-client-image-build]

  -c                    Keep Helm releases and namespaces after the test
  --skip-client-image-build
                        Reuse the existing test client image

Environment:
  KIND_CLUSTER_NAME     Kind cluster name (default: chart-testing)
  K8S                   Kind node image tag when the script creates a cluster
EOF
}

while (($# > 0)); do
  case "$1" in
    -c)
      CLEANUP=0
      ;;
    --skip-client-image-build)
      export SKIP_CLIENT_IMAGE_BUILD=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

for command in docker helm jq kind kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "required command not found: ${command}" >&2
    exit 1
  fi
done

if ! kind get clusters | grep -Fxq "${KIND_CLUSTER_NAME}"; then
  kind_args=(create cluster --name "${KIND_CLUSTER_NAME}")
  if [[ -n "${K8S}" ]]; then
    kind_args+=(--image "kindest/node:${K8S}")
  fi
  kind "${kind_args[@]}"
fi

k() {
  kubectl --context "${KUBE_CONTEXT}" "$@"
}

h() {
  helm --kube-context "${KUBE_CONTEXT}" "$@"
}

image_registry() {
  local without_tag="${1%:*}"
  printf '%s\n' "${without_tag%%/*}"
}

image_repository() {
  local path="${1#*/}"
  printf '%s\n' "${path%:*}"
}

image_tag() {
  printf '%s\n' "${1##*:}"
}

resolve_spire_images() {
  if [[ -n "${SPIRE_SERVER_IMAGE}" || -n "${SPIRE_AGENT_IMAGE}" ]]; then
    SPIRE_SERVER_IMAGE="${SPIRE_SERVER_IMAGE:-${DEFAULT_SPIRE_SERVER_IMAGE}}"
    SPIRE_AGENT_IMAGE="${SPIRE_AGENT_IMAGE:-${DEFAULT_SPIRE_AGENT_IMAGE}}"
    return
  fi

  if docker image inspect "${LOCAL_SPIRE_SERVER_IMAGE}" >/dev/null 2>&1 &&
    docker image inspect "${LOCAL_SPIRE_AGENT_IMAGE}" >/dev/null 2>&1; then
    SPIRE_SERVER_IMAGE="${LOCAL_SPIRE_SERVER_IMAGE}"
    SPIRE_AGENT_IMAGE="${LOCAL_SPIRE_AGENT_IMAGE}"
    return
  fi

  SPIRE_SERVER_IMAGE="${DEFAULT_SPIRE_SERVER_IMAGE}"
  SPIRE_AGENT_IMAGE="${DEFAULT_SPIRE_AGENT_IMAGE}"
}

load_spire_image_if_available() {
  local image="$1"
  if [[ "${image}" == "${DEFAULT_SPIRE_SERVER_IMAGE}" || "${image}" == "${DEFAULT_SPIRE_AGENT_IMAGE}" ]]; then
    return
  fi
  if docker image inspect "${image}" >/dev/null 2>&1; then
    kind load docker-image "${image}" --name "${KIND_CLUSTER_NAME}"
  fi
}

cleanup() {
  set +e
  h uninstall "${BROKER_RELEASE}" --namespace "${APP_A_NAMESPACE}" >/dev/null 2>&1
  h uninstall "${BROKER_RELEASE}" --namespace "${APP_B_NAMESPACE}" >/dev/null 2>&1
  h uninstall "${BROKER_RELEASE}" --namespace "${SERVER_NAMESPACE}" >/dev/null 2>&1
  h uninstall spire --namespace "${SERVER_NAMESPACE}" >/dev/null 2>&1
  k delete namespace "${APP_A_NAMESPACE}" "${APP_B_NAMESPACE}" "${SERVER_NAMESPACE}" --ignore-not-found --wait=true >/dev/null 2>&1
  set -e
}

diagnostics() {
  set +e
  echo "=== Helm releases ==="
  h list --all-namespaces
  echo "=== Kubernetes resources ==="
  k get pods,deployments,statefulsets,daemonsets,jobs --all-namespaces -o wide
  for namespace in "${SERVER_NAMESPACE}" "${APP_A_NAMESPACE}" "${APP_B_NAMESPACE}"; do
    echo "=== Events: ${namespace} ==="
    k get events --namespace "${namespace}" --sort-by=.lastTimestamp
    echo "=== Logs: ${namespace} ==="
    while read -r pod; do
      [[ -n "${pod}" ]] || continue
      k logs --namespace "${namespace}" "${pod}" --all-containers=true --prefix --ignore-errors=true
    done < <(k get pods --namespace "${namespace}" -o name 2>/dev/null)
  done
  set -e
}

on_exit() {
  local exit_code="$1"
  trap - EXIT
  if ((exit_code != 0)); then
    diagnostics
  fi
  if ((CLEANUP == 1)); then
    cleanup
  fi
  exit "${exit_code}"
}

trap 'on_exit $?' EXIT

resolve_spire_images
cleanup

if ! h status spire-crds --namespace "${MANAGEMENT_NAMESPACE}" >/dev/null 2>&1; then
  mapfile -t stale_crds < <(
    k get customresourcedefinitions.apiextensions.k8s.io -o name |
      grep '\.spire\.spiffe\.io$' || true
  )
  if ((${#stale_crds[@]} > 0)); then
    k delete "${stale_crds[@]}" --ignore-not-found
  fi
fi

"${REPO_ROOT}/.github/scripts/prepare-local-chart-deps.sh"

if [[ "${SKIP_CLIENT_IMAGE_BUILD:-0}" != "1" ]]; then
  docker buildx build --load \
    --tag "${CLIENT_IMAGE}" \
    --file "${SCRIPT_DIR}/client/Dockerfile" \
    "${REPO_ROOT}/tests"
fi

docker image inspect "${CLIENT_IMAGE}" >/dev/null
kind load docker-image "${CLIENT_IMAGE}" --name "${KIND_CLUSTER_NAME}"
load_spire_image_if_available "${SPIRE_SERVER_IMAGE}"
load_spire_image_if_available "${SPIRE_AGENT_IMAGE}"

for namespace in "${MANAGEMENT_NAMESPACE}" "${SERVER_NAMESPACE}" "${APP_A_NAMESPACE}" "${APP_B_NAMESPACE}"; do
  k create namespace "${namespace}" --dry-run=client -o yaml | k apply -f -
done

h upgrade --install spire-crds "${REPO_ROOT}/charts/spire-crds" \
  --namespace "${MANAGEMENT_NAMESPACE}" \
  --wait \
  --timeout 3m

h upgrade --install spire "${REPO_ROOT}/charts/spire" \
  --namespace "${SERVER_NAMESPACE}" \
  --values "${SCRIPT_DIR}/spire-values.yaml" \
  --set-string "spire-server.image.registry=$(image_registry "${SPIRE_SERVER_IMAGE}")" \
  --set-string "spire-server.image.repository=$(image_repository "${SPIRE_SERVER_IMAGE}")" \
  --set-string "spire-server.image.tag=$(image_tag "${SPIRE_SERVER_IMAGE}")" \
  --set-string spire-server.image.pullPolicy=IfNotPresent \
  --set-string "spire-agent.image.registry=$(image_registry "${SPIRE_AGENT_IMAGE}")" \
  --set-string "spire-agent.image.repository=$(image_repository "${SPIRE_AGENT_IMAGE}")" \
  --set-string "spire-agent.image.tag=$(image_tag "${SPIRE_AGENT_IMAGE}")" \
  --set-string spire-agent.image.pullPolicy=IfNotPresent \
  --wait \
  --timeout 5m

mapfile -t agent_nodes < <(
  k get pods --namespace "${SERVER_NAMESPACE}" \
    --selector app.kubernetes.io/instance=spire,app.kubernetes.io/name=agent \
    --output custom-columns=NODE:.spec.nodeName,PHASE:.status.phase \
    --no-headers | awk '$2 == "Running" { print $1 }' | sort
)

if ((${#agent_nodes[@]} == 0)); then
  echo "no running SPIRE DaemonSet agents found" >&2
  exit 1
fi

NODE_A="${agent_nodes[0]}"
NODE_B="${agent_nodes[1]:-${agent_nodes[0]}}"
NODE_A_UID="$(k get node "${NODE_A}" -o jsonpath='{.metadata.uid}')"
NODE_B_UID="$(k get node "${NODE_B}" -o jsonpath='{.metadata.uid}')"
AGENT_ALIAS_A="spiffe://example.org/spire/agent/k8s_psat/primary-cluster/${NODE_A_UID}"
AGENT_ALIAS_B="spiffe://example.org/spire/agent/k8s_psat/primary-cluster/${NODE_B_UID}"

create_test_resources() {
  local namespace="$1"
  local broker="$2"
  local target="$3"

  k create serviceaccount "${broker}" --namespace "${namespace}" --dry-run=client -o yaml | k apply -f -
  k create serviceaccount "unauthorized-${broker#broker-}" --namespace "${namespace}" --dry-run=client -o yaml | k apply -f -
  k create configmap "${target}" --namespace "${namespace}" --from-literal=value="${target}" --dry-run=client -o yaml | k apply -f -
}

create_test_resources "${APP_A_NAMESPACE}" broker-a target-a
create_test_resources "${APP_B_NAMESPACE}" broker-b target-b
k create secret generic target-secret-a --namespace "${APP_A_NAMESPACE}" --from-literal=value=secret --dry-run=client -o yaml | k apply -f -

copy_bundle() {
  local namespace="$1"
  k get configmap spire-bundle --namespace "${SERVER_NAMESPACE}" -o json |
    jq --arg namespace "${namespace}" '
      del(
        .metadata.annotations,
        .metadata.creationTimestamp,
        .metadata.labels,
        .metadata.managedFields,
        .metadata.resourceVersion,
        .metadata.uid
      ) |
      .metadata.namespace = $namespace
    ' |
    k apply -f -
}

copy_bundle "${APP_A_NAMESPACE}"
copy_bundle "${APP_B_NAMESPACE}"

install_broker() {
  local namespace="$1"
  local values="$2"
  local workload_agent_alias="$3"

  h upgrade --install "${BROKER_RELEASE}" "${REPO_ROOT}/charts/spire-tcp-broker" \
    --namespace "${namespace}" \
    --values "${values}" \
    --set-string clusterName=broker-pods \
    --set-string controllerManagerClassName=spire-server-spire \
    --set-string server.address=spire-server.spire-server \
    --set-string "workloadAgentAlias=${workload_agent_alias}" \
    --set-string "image.registry=$(image_registry "${SPIRE_AGENT_IMAGE}")" \
    --set-string "image.repository=$(image_repository "${SPIRE_AGENT_IMAGE}")" \
    --set-string "image.tag=$(image_tag "${SPIRE_AGENT_IMAGE}")" \
    --set-string image.pullPolicy=IfNotPresent \
    --wait \
    --timeout 3m
}

install_broker "${APP_A_NAMESPACE}" "${SCRIPT_DIR}/broker-a-values.yaml" "${AGENT_ALIAS_A}"
install_broker "${APP_B_NAMESPACE}" "${SCRIPT_DIR}/broker-b-values.yaml" "${AGENT_ALIAS_B}"

wait_for_entry() {
  local spiffe_id="$1"
  for _ in {1..90}; do
    if k exec statefulset/spire-server --namespace "${SERVER_NAMESPACE}" -c spire-server -- \
      spire-server entry show 2>/dev/null | grep -Fq "${spiffe_id}"; then
      return 0
    fi
    sleep 1
  done
  echo "SPIRE entry did not reconcile: ${spiffe_id}" >&2
  return 1
}

wait_for_entry spiffe://example.org/broker-a
wait_for_entry spiffe://example.org/broker-b
wait_for_entry spiffe://example.org/target-a
wait_for_entry spiffe://example.org/target-b

for namespace in "${APP_A_NAMESPACE}" "${APP_B_NAMESPACE}"; do
  agent_config="$(k get configmap "${BROKER_RELEASE}" --namespace "${namespace}" -o jsonpath='{.data.agent\.conf}')"
  grep -Fq 'disable_workload_api = true' <<<"${agent_config}"
  grep -Fq 'disable_sds_api = true' <<<"${agent_config}"
  grep -Fq 'disable_kubelet_client = true' <<<"${agent_config}"
  for setting in kubelet_ca_path kubelet_read_only_port kubelet_secure_port skip_kubelet_verification node_name_env token_path certificate_path private_key_path use_anonymous_authentication reload_interval; do
    if grep -Fq "${setting}" <<<"${agent_config}"; then
      echo "broker agent config unexpectedly contains kubelet client setting: ${setting}" >&2
      exit 1
    fi
  done
done

run_case() {
  local namespace="$1"
  local name="$2"
  local service_account="$3"
  local node="$4"
  shift 4

  echo "=== Test case: ${namespace}/${name} ==="
  k delete job "${name}" --namespace "${namespace}" --ignore-not-found --wait=true >/dev/null

  jq -n \
    --arg namespace "${namespace}" \
    --arg name "${name}" \
    --arg service_account "${service_account}" \
    --arg node "${node}" \
    --arg image "${CLIENT_IMAGE}" \
    --args '
      $ARGS.positional as $arguments |
      {
        apiVersion: "batch/v1",
        kind: "Job",
        metadata: {name: $name, namespace: $namespace},
        spec: {
          backoffLimit: 0,
          template: {
            metadata: {labels: {"app.kubernetes.io/name": "spire-tcp-broker-client"}},
            spec: {
              restartPolicy: "Never",
              serviceAccountName: $service_account,
              nodeSelector: {"kubernetes.io/hostname": $node},
              containers: [{
                name: "brokerclient",
                image: $image,
                imagePullPolicy: "Never",
                args: $arguments,
                securityContext: {
                  allowPrivilegeEscalation: false,
                  capabilities: {drop: ["ALL"]},
                  readOnlyRootFilesystem: true,
                  runAsNonRoot: true
                },
                volumeMounts: [{
                  name: "workload-api",
                  mountPath: "/run/spire/agent-sockets",
                  readOnly: true
                }]
              }],
              volumes: [{
                name: "workload-api",
                hostPath: {
                  path: "/run/spire/agent-sockets",
                  type: "Directory"
                }
              }]
            }
          }
        }
      }
    ' -- "$@" | k apply -f -

  if ! k wait --namespace "${namespace}" --for=condition=complete "job/${name}" --timeout=90s; then
    k get pods --namespace "${namespace}" --selector "job-name=${name}" -o wide
    k logs --namespace "${namespace}" "job/${name}" --all-containers=true --ignore-errors=true
    return 1
  fi
  k logs --namespace "${namespace}" "job/${name}" --all-containers=true
}

run_case "${APP_A_NAMESPACE}" positive-a broker-a "${NODE_A}" \
  -expected-own-spiffe=spiffe://example.org/broker-a \
  -broker-addr=dns:///spire-tcp-broker.broker-app-a.svc:8443 \
  -ref-type=object -plural=configmaps -group=core \
  -namespace=broker-app-a -name=target-a \
  -expected-spiffe=spiffe://example.org/target-a

run_case "${APP_B_NAMESPACE}" positive-b broker-b "${NODE_B}" \
  -expected-own-spiffe=spiffe://example.org/broker-b \
  -broker-addr=dns:///spire-tcp-broker.broker-app-b.svc:8443 \
  -ref-type=object -plural=configmaps -group=core \
  -namespace=broker-app-b -name=target-b \
  -expected-spiffe=spiffe://example.org/target-b

run_case "${APP_A_NAMESPACE}" cross-broker-mtls broker-a "${NODE_A}" \
  -timeout=15s \
  -expected-own-spiffe=spiffe://example.org/broker-a \
  -broker-addr=dns:///spire-tcp-broker.broker-app-b.svc:8443 \
  -ref-type=object -plural=configmaps -group=core \
  -namespace=broker-app-b -name=target-b \
  -expect-err=Unavailable

run_case "${APP_A_NAMESPACE}" unlisted-workload-no-identity unauthorized-a "${NODE_A}" \
  -timeout=10s -expect-own-error

run_case "${APP_A_NAMESPACE}" pid-reference-denied broker-a "${NODE_A}" \
  -expected-own-spiffe=spiffe://example.org/broker-a \
  -broker-addr=dns:///spire-tcp-broker.broker-app-a.svc:8443 \
  -ref-type=pid -pid=1 \
  -expect-err=PermissionDenied

run_case "${APP_A_NAMESPACE}" kubernetes-rbac-denied broker-a "${NODE_A}" \
  -expected-own-spiffe=spiffe://example.org/broker-a \
  -broker-addr=dns:///spire-tcp-broker.broker-app-a.svc:8443 \
  -ref-type=object -plural=secrets -group=core \
  -namespace=broker-app-a -name=target-secret-a \
  -expect-err=PermissionDenied

run_case "${APP_A_NAMESPACE}" kubernetes-object-not-found broker-a "${NODE_A}" \
  -expected-own-spiffe=spiffe://example.org/broker-a \
  -broker-addr=dns:///spire-tcp-broker.broker-app-a.svc:8443 \
  -ref-type=object -plural=configmaps -group=core \
  -namespace=broker-app-a -name=does-not-exist \
  -expect-err=NotFound

run_case "${APP_A_NAMESPACE}" static-entry-alias-isolation broker-a "${NODE_A}" \
  -expected-own-spiffe=spiffe://example.org/broker-a \
  -broker-addr=dns:///spire-tcp-broker.broker-app-a.svc:8443 \
  -ref-type=object -plural=configmaps -group=core \
  -namespace=broker-app-b -name=target-b \
  -expect-empty

echo "All spire-tcp-broker integration cases passed."
