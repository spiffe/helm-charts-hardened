#!/usr/bin/env bash
# shellcheck disable=SC2317

set -xe

SCRIPT="$(readlink -f "$0")"
SCRIPTPATH="$(dirname "${SCRIPT}")"
TESTDIR="${SCRIPTPATH}/../../.github/tests"
#DEPS="${TESTDIR}/dependencies"

# shellcheck source=/dev/null
source "${SCRIPTPATH}/../../.github/scripts/parse-versions.sh"
# shellcheck source=/dev/null
source "${TESTDIR}/common.sh"

CLEANUP=1
BROKER=0

for i in "$@"; do
  case $i in
    -c)
      CLEANUP=0
      shift # past argument=value
      ;;
    -b)
      BROKER=1
      shift # past argument=value
      ;;
  esac
done

# With -b, test the spire-ha-agent broker api instead of the delegated api.
# Broker mode also supports federated trust bundles, so federate the ha-agent's own entry and a
# dedicated federation-test workload entry with the other.invalid trust domain on both sides. Delegated
# mode only tolerates the local and spire-ha bundles, so none of this may apply without -b.

# Placeholder bundle endpoint for other.invalid. Its ClusterFederatedTrustDomain carries the bundle
# verbatim, but the CRD requires an endpoint alongside it. This name is never meant to answer, it
# just has to be ours: .invalid can never be registered, and coredns pins it to 127.0.0.1 below.
FEDERATION_ENDPOINT_HOST=spire-server-federation.other.invalid
BROKER_MODE_ARGS=()
BROKER_SOCKET_ARGS_A=()
BROKER_SOCKET_ARGS_B=()
if [ "${BROKER}" -eq 1 ]; then
  BROKER_MODE_ARGS=(--set "spire-ha-agent.mode=broker")
  BROKER_SOCKET_ARGS_A=(
    --set downstream-spire-agent-bottom-turtle-ha-a.sockets.broker.enabled=true
    --set downstream-spire-agent-bottom-turtle-ha-a.sockets.broker.mountOnHost=true
    --set 'internal-spire-server-bottom-turtle-ha-a.controllerManager.identities.clusterSPIFFEIDs.spire-ha-agent.federatesWith={spire-ha,other.invalid}'
    --set 'internal-spire-server-bottom-turtle-ha-a.controllerManager.identities.clusterSPIFFEIDs.federation-test.federatesWith={other.invalid}'
    --set 'internal-spire-server-bottom-turtle-ha-a.controllerManager.identities.clusterSPIFFEIDs.federation-test.podSelector.matchLabels.app=federation-test'
  )
  BROKER_SOCKET_ARGS_B=(
    --set downstream-spire-agent-bottom-turtle-ha-b.sockets.broker.enabled=true
    --set downstream-spire-agent-bottom-turtle-ha-b.sockets.broker.mountOnHost=true
    --set 'internal-spire-server-bottom-turtle-ha-b.controllerManager.identities.clusterSPIFFEIDs.spire-ha-agent.federatesWith={spire-ha,other.invalid}'
    --set 'internal-spire-server-bottom-turtle-ha-b.controllerManager.identities.clusterSPIFFEIDs.federation-test.federatesWith={other.invalid}'
    --set 'internal-spire-server-bottom-turtle-ha-b.controllerManager.identities.clusterSPIFFEIDs.federation-test.podSelector.matchLabels.app=federation-test'
  )
fi

if [ "x${GITHUB_JOB}" != "x" ]; then
  echo "Running in GitHub"
else
  echo "Do not run this script on your own box. For testing, it deploys a testing local spire ha setup using sudo. This is likely not what you want. Only use this script as a reference."
  exit 1
fi

teardown() {
  echo ---------------------------
  docker exec -i chart-testing-worker /bin/bash -c "more /var/lib/kubelet/pods/*/volumes/kubernetes.io~empty-dir/disk-keymanager/keys.json /var/lib/kubelet/pods/*/volumes/kubernetes.io~empty-dir/spire-agent-persistence/agent-data.json | cat"
  sudo systemctl status spire-server@a || true
  sudo systemctl status spire-server@b || true
  sudo systemctl status spire-server@other || true
  kubectl describe job federation-test || true
  kubectl logs job/federation-test || true
  for JOB in image-push image-pull image-push-denied; do
    dump_job "${JOB}"
  done
  dump_zot
  sudo systemctl status spire-ha-agent@main || true
  sudo systemctl status spiffe-socat-unix@k8s-kubelet-2 || true
  sudo systemctl status spiffe-socat-unix@k8s-kubelet-3 || true
  sudo systemctl status spiffe-socat-unix@k8s-kubelet-4 || true
  dump_kubelet_all
  sudo spire-server entry show -instance a || true
  sudo spire-server entry show -instance b || true
  sudo systemctl status spire-controller-manager@a || true
  sudo systemctl status spire-controller-manager@b || true
  sudo systemctl status spire-agent@a || true
  sudo systemctl status spire-agent@b || true
  sudo systemctl status spire-trust-sync@a || true
  sudo systemctl status spire-trust-sync@b || true
  sudo systemctl status spiffe-socat-unix@k8s-spire-server-a || true
  sudo systemctl status spiffe-socat-unix@k8s-spire-server-b || true
  sudo systemctl status spiffe-socat-unix@k8s-spire-agent-2-a || true
  sudo systemctl status spiffe-socat-unix@k8s-spire-agent-2-b || true
  sudo systemctl status spiffe-socat-unix@k8s-spire-agent-3-a || true
  sudo systemctl status spiffe-socat-unix@k8s-spire-agent-3-b || true
  sudo systemctl status spiffe-socat-unix@k8s-spire-agent-4-a || true
  sudo systemctl status spiffe-socat-unix@k8s-spire-agent-4-b || true
  sudo spire-server bundle list -socketPath /var/run/spire/server/sockets/a/private/api.sock || true
  sudo spire-server bundle list -socketPath /var/run/spire/server/sockets/b/private/api.sock || true
  kubectl exec -i -n spire-server spire-a-internal-server-0 -- spire-server entry show || true
  kubectl exec -i -n spire-server spire-b-internal-server-0 -- spire-server entry show || true
  kubectl exec -i -n spire-server spire-a-internal-server-0 -- spire-server agent list -output json | yq e . - -P || true
  kubectl exec -i -n spire-server spire-b-internal-server-0 -- spire-server agent list -output json | yq e . - -P || true
  kubectl get pods -A -o wide || true
  kubectl describe daemonset pods -n spire-system || true
  kubectl get configmap -n spire-system || true
  kubectl get configmap -n spire-system spire-a-agent-downstream -o yaml || true
  kubectl get endpoints -n spire-server -o yaml || true

  print_helm_releases

  if [[ "$1" -ne 0 ]]; then
    get_namespace_details spire-server spire-system
    kubectl describe pod -n spire-system
  fi

  if [ "${CLEANUP}" -eq 1 ]; then
    kubectl delete job federation-test 2>/dev/null || true
    kubectl delete job image-push image-pull image-push-denied 2>/dev/null || true
    helm uninstall --namespace zot zot 2>/dev/null || true
    kubectl delete ns zot 2>/dev/null || true
    helm uninstall --namespace spire-mgmt spire-b 2>/dev/null || true
    helm uninstall --namespace spire-mgmt spire-a 2>/dev/null || true
    helm uninstall --namespace spire-mgmt spire 2>/dev/null || true
    kubectl delete ns spire-server 2>/dev/null || true
    kubectl delete ns spire-system 2>/dev/null || true
    kubectl delete ns spire-mgmt 2>/dev/null || true
  fi
}

trap 'EC=$? && trap - SIGTERM && teardown $EC' SIGINT SIGTERM EXIT

wait_for_healthcheck() {
  local app="$1"
  local socket="$2"
  local timeout=30
  local count=0
  while [ "$count" -lt "$timeout" ]; do
    rc=0
    sudo "$app" healthcheck -socketPath "$socket" || rc=$?
    if [ "$rc" -eq 0 ]; then
      return 0
    fi
    sleep 1
    ((count++)) || true
  done
  return 1
}

wait_for_trust_sync() {
  local socket="$1"
  local timeout=30
  local count=0
  while [ "$count" -lt "$timeout" ]; do
    entries=$(sudo spire-server bundle list -socketPath "$socket" | wc -l)
    if [ "$entries" -ne 0 ]; then
      return 0
    fi
    sleep 1
    ((count++)) || true
  done
  return 1
}

# Dump everything useful about a job in one block. The trace goes to stderr while command
# output goes to stdout, and the two are separate streams in the CI log, so anything printed
# here can interleave or drop. Suspend the trace, merge each command's streams, and bracket
# the whole thing so it stays readable.
dump_job() {
  local job="$1"
  set +x
  echo "===== BEGIN ${job} ====="
  kubectl get pods -l "job-name=${job}" -o wide 2>&1 || true
  kubectl describe job "${job}" 2>&1 || true
  # Pod events are where image pull and volume failures show up; the job has none of this.
  kubectl describe pod -l "job-name=${job}" 2>&1 || true
  # --prefix labels each line with its container. These jobs have three init containers and
  # the interesting output is rarely the last one.
  kubectl logs "job/${job}" --all-containers --prefix 2>&1 || true
  # Everything kubelet said about this pod on the node that ran it. Filtering on the image
  # misses the credential provider path, which names the pod and service account instead,
  # and only the first pull attempt carries the real error; the retries are all backoff.
  local pod node
  for pod in $(kubectl get pods -l "job-name=${job}" -o name 2>/dev/null | cut -d/ -f2); do
    node="$(kubectl get pod "${pod}" -o jsonpath='{.spec.nodeName}' 2>/dev/null)"
    [ -n "${node}" ] || continue
    echo "----- kubelet ${node} for pod ${pod} -----"
    # Only this pod. A broader filter matches every provider line since boot and the
    # window fills long before the pull happens.
    docker exec -i "${node}" journalctl -u kubelet --no-pager 2>&1 \
      | grep -F "${pod}" | head -60 || true
    # The plugin exec is logged against the image and plugin name, not the pod, so a pod
    # filter hides exactly the line that says whether it ran and what it returned.
    echo "----- kubelet ${node} credential provider decisions -----"
    docker exec -i "${node}" journalctl -u kubelet --no-pager 2>&1 \
      | grep -E 'exec plugin|image credentials|k8s-image-cred|without credentials|zot\.production\.other|[Ss]ervice account' \
      | tail -40 || true
  done
  echo "===== END ${job} ====="
  set -x
}

# Same treatment as dump_job. zot logs at debug, and its rejection reason for a bearer
# token only appears there, so take the whole log rather than a tail.
dump_zot() {
  set +x
  echo "===== BEGIN zot ====="
  kubectl get pods -n zot -o wide 2>&1 || true
  kubectl describe pod -n zot -l app.kubernetes.io/name=zot 2>&1 || true
  kubectl logs -n zot -l app.kubernetes.io/name=zot --all-containers --prefix 2>&1 || true
  echo "===== END zot ====="
  set -x
}

# Whether kubelet was configured with the image credential provider at all, and whether it
# ran it. The kubeadm patch landing is the whole question when a pull comes back anonymous.
dump_kubelet() {
  local node="$1"
  set +x
  echo "===== BEGIN kubelet ${node} ====="
  docker exec -i "${node}" cat /var/lib/kubelet/kubeadm-flags.env 2>&1 || true
  docker exec -i "${node}" ps ax 2>&1 | grep '[k]ubelet' || true
  docker exec -i "${node}" ls -l /credential-plugins /etc/kubernetes/credential-provider-config.yaml 2>&1 || true
  # The plugin reaches the workload API through this bridge. If the socket is absent the
  # plugin fails immediately, kubelet falls back to anonymous, and the pull 401s.
  docker exec -i "${node}" ls -l /var/run/spiffe/socat/unix/k8s-kubelet/public/ 2>&1 || true
  # Only the registry we care about. A broad credential grep is pure noise at v=4, which
  # logs a provider line for every image pull on the node.
  docker exec -i "${node}" journalctl -u kubelet --no-pager 2>&1 \
    | grep -E 'zot\.production\.other' -A3 | tail -60 || true
  echo "===== END kubelet ${node} ====="
  set -x
}

# Run the credential provider by hand with the same arguments, environment and request
# shape kubelet uses. An image pull that comes back anonymous tells us nothing about why;
# this prints the plugin's own stdout and stderr.
probe_credential_provider() {
  local node="$1"
  local token args env_kv
  set +x
  echo "===== BEGIN credential-provider probe ${node} ====="
  # The pull job's service account is created with the job, which has not been applied
  # yet; create it up front so the probe can mint the same token kubelet would.
  kubectl create serviceaccount zot-pull --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 || true
  # kubelet looks credentials up by the tagless repository and passes that same string
  # to the plugin, so send the repo rather than a tagged reference.
  # Same audience the kubelet config requests via tokenAttributes.
  if ! token="$(kubectl create token zot-pull --audience=spire-identity-exchange 2>&1)"; then
    echo "could not mint a service account token: ${token}"
    echo "===== END credential-provider probe ${node} ====="
    set -x
    return 0
  fi
  args="$(yq e '.providers[0].args | join(" ")' "${SCRIPTPATH}/../../.github/kind/conf/credential-provider-config.yaml")"
  env_kv="$(yq e '.providers[0].env[] | .name + "=" + .value' "${SCRIPTPATH}/../../.github/kind/conf/credential-provider-config.yaml" | tr '\n' ' ')"
  # Word splitting on args and env_kv is intended here.
  # shellcheck disable=SC2086
  docker exec -i "${node}" env ${env_kv} /credential-plugins/k8s-image-cred-spire-identity-exchange ${args} <<EOF 2>&1 || true
{"apiVersion":"credentialprovider.kubelet.k8s.io/v1","kind":"CredentialProviderRequest","image":"zot.production.other/test/busybox","serviceAccountToken":"${token}"}
EOF
  echo "===== END credential-provider probe ${node} ====="
  set -x
}

dump_kubelet_all() {
  for NODE in $(kubectl get nodes -o name 2>/dev/null | cut -d/ -f2); do
    dump_kubelet "${NODE}"
  done
}

# kubectl wait --for=condition=complete blocks the full timeout when a job has already
# failed, which makes every failure look like a hang and delays the dump by minutes. Poll
# both terminal conditions instead.
wait_for_job() {
  local job="$1"
  local timeout="${2:-120}"
  local count=0
  while [ "$count" -lt "$timeout" ]; do
    if kubectl get job "$job" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null | grep -q True; then
      return 0
    fi
    if kubectl get job "$job" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null | grep -q True; then
      echo "job/$job failed"
      dump_job "$job"
      return 1
    fi
    sleep 1
    ((count++)) || true
  done
  echo "job/$job did not finish within ${timeout}s"
  dump_job "$job"
  return 1
}

wait_for_socket() {
  local socket="$1"
  local timeout=30
  local count=0
  while [ "$count" -lt "$timeout" ]; do
    if [ -S "$socket" ]; then
      return 0
    fi
    sleep 1
    ((count++)) || true
  done
  return 1
}

wait_for_jwt() {
  local socket="$1"
  local timeout=30
  local count=0
  while [ "$count" -lt "$timeout" ]; do
      rc=0
      sudo spire-agent api fetch jwt -audience test -socketPath "$socket" || rc=$?
      if [ "$rc" -eq 0 ]; then
        return 0
      fi
      sleep 1
      ((count++)) || true
  done
  return 1
}

wait_for_entry_federation() {
  local pod="$1"
  local trustdomain="$2"
  local timeout=60
  local count=0
  while [ "$count" -lt "$timeout" ]; do
    if kubectl exec -i -n spire-server "$pod" -- spire-server entry show -spiffeID spiffe://production.other/spire-ha-agent | grep -q "$trustdomain"; then
      return 0
    fi
    sleep 2
    ((count++)) || true
  done
  return 1
}

run_federation_test_job() {
  kubectl delete job federation-test 2>/dev/null || true
  # Inject the images from the charts into the job so they always sync up
  yq e "(.spec.template.spec.initContainers[] | select(.name == \"static-busybox\") | .image) = \"${BUSYBOX_IMAGE}\" | (.spec.template.spec.containers[] | select(.name == \"main\") | .image) = \"${AGENT_IMAGE}\"" \
    "${SCRIPTPATH}/federation-test-job.yaml" | kubectl apply -f -
  kubectl wait --for=condition=complete --timeout=240s job/federation-test
  kubectl logs job/federation-test | grep FEDERATION-OK
}

"${SCRIPTPATH}/../../.github/scripts/prepare-local-chart-deps.sh"

# Get the package repo and install the packages
sudo curl -s -o /etc/apt/sources.list.d/spire-examples.list https://raw.githubusercontent.com/spiffe/spire-examples/refs/heads/main/examples/debs/amd64/spire-examples.list
sudo apt-get update
sudo apt-get install -y spire-common spire-agent spire-server spire-controller-manager spiffe-socat-unix socat spire-trust-sync spiffe-helper spire-ha-agent

# Set our testing trust domain
sudo sed -i 's/example.org/production.other/' /etc/spiffe/default-trust-domain.env

# A trust domain has one OIDC discovery endpoint, but the packaged root server config
# advertises oidc-discovery-provider.<trust domain> while the charts advertise
# oidc-discovery.<trust domain>. The identity exchange checks the iss claim by exact string,
# so a JWT-SVID minted by a root server, which is what kubelet's credential provider
# presents, is rejected unless the two agree. Align the roots with the charts.
sudo sed -i 's|jwt_issuer = "https://oidc-discovery-provider\.|jwt_issuer = "https://oidc-discovery.|' /etc/spire/server/default.conf
grep jwt_issuer /etc/spire/server/default.conf

if [ "${BROKER}" -eq 1 ]; then
  # Pull the federation test job images out of the charts so they always sync up.
  AGENT_IMAGE=$(helm template t charts/spire -s charts/spire-agent/templates/daemonset.yaml --values "${COMMON_TEST_YOUR_VALUES}" --set spire-agent.enabled=true | yq e 'select(.kind=="DaemonSet") | .spec.template.spec.containers[] | select(.name=="spire-agent") | .image' -)
  BUSYBOX_IMAGE=$(helm template t charts/spire -s charts/spiffe-oidc-discovery-provider/templates/tests/test-keys.yaml --values "${COMMON_TEST_YOUR_VALUES}" --set spiffe-oidc-discovery-provider.enabled=true | yq e 'select(.kind=="Pod") | .spec.initContainers[] | select(.name=="static-busybox") | .image' -)
  echo "federation test job images: ${AGENT_IMAGE} ${BUSYBOX_IMAGE}"

  # Mint a trust bundle for a foreign trust domain (other.invalid) to test federated trust bundle
  # support. A throwaway third spire-server instance produces a genuine spiffe format bundle
  # carrying both x509 and jwt authorities. The instance env file overrides the global trust
  # domain since systemd applies later EnvironmentFiles last.
  sudo /bin/bash -c '(echo SPIFFE_TRUST_DOMAIN=other.invalid; echo SPIRE_BIND_PORT=8083) > /etc/spire/server/other.env'
  sudo systemctl start spire-server@other
  wait_for_healthcheck spire-server /run/spire/server/sockets/other/private/api.sock
  sudo spire-server bundle show -format spiffe -socketPath /run/spire/server/sockets/other/private/api.sock | sudo tee /tmp/other-invalid-bundle.json > /dev/null
  sudo systemctl stop spire-server@other
  grep -q '"x509-svid"' /tmp/other-invalid-bundle.json
  grep -q '"jwt-svid"' /tmp/other-invalid-bundle.json

  # Seed the bundle into each server's ClusterFederatedTrustDomain so the controller manager can
  # create the entries that federate with other.invalid on its first reconcile. Loading it after
  # the install instead leaves the ha-agent without an SVID for the whole helm --wait window.
  # The CRD requires an endpoint even when the bundle is supplied verbatim; .invalid can never be
  # registered and coredns pins the name locally, so the endpoint never answers. That is fine,
  # spire keeps a federated bundle when a refresh fails.
  FTD_A=internal-spire-server-bottom-turtle-ha-a.controllerManager.identities.clusterFederatedTrustDomains.other
  FTD_B=internal-spire-server-bottom-turtle-ha-b.controllerManager.identities.clusterFederatedTrustDomains.other
  BROKER_SOCKET_ARGS_A+=(
    --set "${FTD_A}.trustDomain=other.invalid"
    --set "${FTD_A}.bundleEndpointProfile.type=https_web"
    --set "${FTD_A}.bundleEndpointURL=https://${FEDERATION_ENDPOINT_HOST}"
    --set-file "${FTD_A}.trustDomainBundle=/tmp/other-invalid-bundle.json"
  )
  BROKER_SOCKET_ARGS_B+=(
    --set "${FTD_B}.trustDomain=other.invalid"
    --set "${FTD_B}.bundleEndpointProfile.type=https_web"
    --set "${FTD_B}.bundleEndpointURL=https://${FEDERATION_ENDPOINT_HOST}"
    --set-file "${FTD_B}.trustDomainBundle=/tmp/other-invalid-bundle.json"
  )
fi

# register some workloads with the spire server using manifests
sudo mkdir -p /etc/spire/server/a/manifests/ /etc/spire/server/b/manifests/
sudo cp "${SCRIPTPATH}/example-manifests"/* /etc/spire/server/a/manifests/
sudo cp "${SCRIPTPATH}/example-manifests"/* /etc/spire/server/b/manifests/

# For testing, help speed up the sync
sudo rm -f /etc/spire/server/a/manifests/node1-k8s-spire-server.yaml
sudo rm -f /etc/spire/server/b/manifests/node1-k8s-spire-server.yaml

# Since we are running the two root spire servers on the same machine, we need to ensure ports do not conflict for server b
sudo /bin/bash -c 'echo SPIRE_BIND_PORT=8082 > /etc/spire/server/b.env'
sudo /bin/bash -c '(echo METRICS_BIND_ADDRESS="0.0.0.0:9125"; echo HEALTH_PROBE_BIND_ADDRESS="0.0.0.0:9126") > /etc/spire/controller-manager/b.env'

# Startup servers and make sure they are ready
sudo systemctl start spire-server@a spire-server@b spire-controller-manager@a spire-controller-manager@b
wait_for_healthcheck spire-server /run/spire/server/sockets/a/private/api.sock
wait_for_healthcheck spire-server /run/spire/server/sockets/b/private/api.sock

# Configure our agents. For the test, create join tokens for both agents. You should really use a node attestor other then join tokens such as tpm-direct, http_challenge, or a cloud provider one
JOIN_TOKEN_A=$(sudo spire-server token generate -spiffeID spiffe://production.other/agent/node1 -socketPath /run/spire/server/sockets/a/private/api.sock | awk '{print "\""$2"\""}')
JOIN_TOKEN_B=$(sudo spire-server token generate -spiffeID spiffe://production.other/agent/node1 -socketPath /run/spire/server/sockets/b/private/api.sock | awk '{print "\""$2"\""}')
export JOIN_TOKEN_A
export JOIN_TOKEN_B
sudo /bin/bash -c "echo JOIN_TOKEN=${JOIN_TOKEN_A} > /etc/spire/agent/a.env"
sudo /bin/bash -c "echo JOIN_TOKEN=${JOIN_TOKEN_B} > /etc/spire/agent/b.env"
sudo /bin/bash -c "echo SPIRE_SERVER_PORT=8082 >> /etc/spire/agent/b.env"

# Since we are running the two root spire servers on the same machine, we need to configure the trust sync instances to point to the opposite server
sudo /bin/bash -c 'echo "SPIRE_SERVER_SOCKET=/var/run/spire/server/sockets/b/private/api.sock" > /etc/spire/trust-sync/a.conf'
sudo /bin/bash -c 'echo "SPIRE_SERVER_SOCKET=/var/run/spire/server/sockets/a/private/api.sock" > /etc/spire/trust-sync/b.conf'

# Startup the agent
sudo systemctl start spire-agent@a spire-agent@b
sudo systemctl start spire-trust-sync@a spire-trust-sync@b
wait_for_healthcheck spire-agent /var/run/spire/agent/sockets/a/public/api.sock
wait_for_healthcheck spire-agent /var/run/spire/agent/sockets/b/public/api.sock
wait_for_trust_sync /var/run/spire/server/sockets/a/private/api.sock
wait_for_trust_sync /var/run/spire/server/sockets/b/private/api.sock

sudo cp "${SCRIPTPATH}/example-manifests"/node1-k8s-spire-server.yaml /etc/spire/server/a/manifests/
sudo cp "${SCRIPTPATH}/example-manifests"/node1-k8s-spire-server.yaml /etc/spire/server/b/manifests/

# Startup the socat bridge to allow the k8s spire servers to get an identity/trust bundles from the host
sudo systemctl start spiffe-socat-unix@k8s-spire-server-a spiffe-socat-unix@k8s-spire-server-b
wait_for_healthcheck spire-agent /var/run/spiffe/socat/unix/k8s-spire-server-a/public/spire-agent.sock
wait_for_healthcheck spire-agent /var/run/spiffe/socat/unix/k8s-spire-server-b/public/spire-agent.sock
wait_for_jwt /var/run/spiffe/socat/unix/k8s-spire-server-a/public/spire-agent.sock
wait_for_jwt /var/run/spiffe/socat/unix/k8s-spire-server-b/public/spire-agent.sock

# Configure and start up the socat bridges to allow the k8s spire-agents to get an identity/trust bundles from the host.
# We only have one vm mapped to multiple k8s virtual nodes in kind, so we run a pair per k8s virtual node. Normally you would only run one pair per host/vm.
sudo /bin/bash -c "echo SPIFFE_INSTANCE=a > /etc/spiffe/socat/unix/k8s-spire-agent-2-a.conf"
sudo /bin/bash -c "echo SPIFFE_INSTANCE=a > /etc/spiffe/socat/unix/k8s-spire-agent-3-a.conf"
sudo /bin/bash -c "echo SPIFFE_INSTANCE=a > /etc/spiffe/socat/unix/k8s-spire-agent-4-a.conf"
sudo /bin/bash -c "echo SPIFFE_INSTANCE=b > /etc/spiffe/socat/unix/k8s-spire-agent-2-b.conf"
sudo /bin/bash -c "echo SPIFFE_INSTANCE=b > /etc/spiffe/socat/unix/k8s-spire-agent-3-b.conf"
sudo /bin/bash -c "echo SPIFFE_INSTANCE=b > /etc/spiffe/socat/unix/k8s-spire-agent-4-b.conf"
sudo systemctl start spiffe-socat-unix@k8s-spire-agent-2-a spiffe-socat-unix@k8s-spire-agent-2-b
sudo systemctl start spiffe-socat-unix@k8s-spire-agent-3-a spiffe-socat-unix@k8s-spire-agent-3-b
sudo systemctl start spiffe-socat-unix@k8s-spire-agent-4-a spiffe-socat-unix@k8s-spire-agent-4-b
wait_for_healthcheck spire-agent /var/run/spiffe/socat/unix/k8s-spire-agent-2-a/public/api.sock
wait_for_healthcheck spire-agent /var/run/spiffe/socat/unix/k8s-spire-agent-2-b/public/api.sock
wait_for_healthcheck spire-agent /var/run/spiffe/socat/unix/k8s-spire-agent-3-a/public/api.sock
wait_for_healthcheck spire-agent /var/run/spiffe/socat/unix/k8s-spire-agent-3-b/public/api.sock
wait_for_healthcheck spire-agent /var/run/spiffe/socat/unix/k8s-spire-agent-4-a/public/api.sock
wait_for_healthcheck spire-agent /var/run/spiffe/socat/unix/k8s-spire-agent-4-b/public/api.sock
wait_for_jwt /var/run/spiffe/socat/unix/k8s-spire-agent-2-a/public/api.sock
wait_for_jwt /var/run/spiffe/socat/unix/k8s-spire-agent-2-b/public/api.sock
wait_for_jwt /var/run/spiffe/socat/unix/k8s-spire-agent-3-a/public/api.sock
wait_for_jwt /var/run/spiffe/socat/unix/k8s-spire-agent-3-b/public/api.sock
wait_for_jwt /var/run/spiffe/socat/unix/k8s-spire-agent-4-a/public/api.sock
wait_for_jwt /var/run/spiffe/socat/unix/k8s-spire-agent-4-b/public/api.sock

# Start the host spire-ha-agent. It merges the two root agents into one workload API, which is
# what lets host services keep their identity when a single root server goes away. The compiled
# in defaults already point at /var/run/spire/agent/sockets/{a,b}/private/admin.sock and listen
# on the main instance socket, and the packaged agent config already lists the ha-agent in its
# authorized_delegates, so no configuration is needed.
sudo systemctl start spire-ha-agent@main
# Not wait_for_healthcheck: that calls the grpc.health.v1 service, which the ha-agent does
# not serve, so it always reports "unable to determine health". Not wait_for_jwt either:
# the ha-agent attests callers by pid, and the cli invoking it is in no registered unit.
# Readiness is proven through the bridges below, where the caller does have an entry.
wait_for_socket /var/run/spire/agent/sockets/main/public/api.sock

# Bridge the merged workload API into each virtual node for kubelet's image credential provider.
# A real deployment runs one ha-agent per host and kubelet talks to it directly. Here a single VM
# backs three virtual nodes, so we put one socat instance in front of the shared ha-agent per
# node. The ha-agent attests each caller by pid, so every bridge resolves to its own entry and
# each node still gets a distinct identity.
sudo /bin/bash -c "echo SPIFFE_INSTANCE=main > /etc/spiffe/socat/unix/k8s-kubelet-2.conf"
sudo /bin/bash -c "echo SPIFFE_INSTANCE=main > /etc/spiffe/socat/unix/k8s-kubelet-3.conf"
sudo /bin/bash -c "echo SPIFFE_INSTANCE=main > /etc/spiffe/socat/unix/k8s-kubelet-4.conf"
sudo systemctl start spiffe-socat-unix@k8s-kubelet-2 spiffe-socat-unix@k8s-kubelet-3 spiffe-socat-unix@k8s-kubelet-4
# These front the ha-agent rather than a spire-agent, so healthcheck does not apply here
# either. Fetching an svid is the real signal: it exercises the bridge, the ha-agent and
# whichever root agent answered.
wait_for_jwt /var/run/spiffe/socat/unix/k8s-kubelet-2/public/api.sock
wait_for_jwt /var/run/spiffe/socat/unix/k8s-kubelet-3/public/api.sock
wait_for_jwt /var/run/spiffe/socat/unix/k8s-kubelet-4/public/api.sock

# Deploy an ingress controller
IP=$(kubectl get nodes chart-testing-control-plane -o go-template='{{ range .status.addresses }}{{ if eq .type "InternalIP" }}{{ .address }}{{ end }}{{ end }}')
helm upgrade --install ingress-nginx ingress-nginx --version "$VERSION_INGRESS_NGINX" --repo "$HELM_REPO_INGRESS_NGINX" \
  --namespace ingress-nginx \
  --create-namespace \
  --set "controller.extraArgs.enable-ssl-passthrough=,controller.admissionWebhooks.enabled=false,controller.service.type=ClusterIP,controller.service.externalIPs[0]=$IP" \
  --set controller.ingressClassResource.default=true \
  --wait

# Test the ingress controller. Should 404 as there is no services yet.
common_test_url "$IP"

# Get the host IP And add spire-server-[ab].${trust_domain} records to it so the spire-servers can talk back to root servers running on the host
HOSTIP=$(ip addr show docker0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
kubectl get configmap -n kube-system coredns -o yaml | grep hosts || kubectl get configmap -n kube-system coredns -o yaml | sed "/ready/a\        hosts {\n           fallthrough\n        }" | kubectl apply -f -
kubectl get configmap -n kube-system coredns -o yaml | grep production.other || kubectl get configmap -n kube-system coredns -o yaml | sed "/hosts/a\           $HOSTIP spire-server-a.production.other\n           $IP oidc-discovery.production.other\n           $HOSTIP spire-server-b.production.other\n           $IP zot.production.other\n           $IP spire-identity-exchange-rest.production.other\n           127.0.0.1 $FEDERATION_ENDPOINT_HOST\n" | kubectl apply -f -
kubectl rollout restart -n kube-system deployment/coredns
kubectl rollout status -n kube-system -w --timeout=1m deploy/coredns

# Install the common components
helm upgrade --install --create-namespace --namespace spire-mgmt --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/spire-values.yaml" \
  spire charts/spire-nested \
  --set tags.haAgentCommon=true \
  --set "global.spire.namespaces.create=true" \
  --set "global.spire.ingressControllerType=ingress-nginx" \
  --set "spiffe-oidc-discovery-provider.ingress.enabled=true" \
  --set "spireIdentityExchange.tls.rest.enabled=true" \
  --set "spireIdentityExchange.tls.rest.ingress.enabled=true" \
  --set "spireIdentityExchange.spiffe.rest.enabled=true" \
  --set "spireIdentityExchange.spiffe.rest.ingress.enabled=true" \
  "${BROKER_MODE_ARGS[@]}"

# Create spire-identity-exchange cert for testing.
mkdir -p certs
openssl req -x509 -newkey rsa:2048 \
    -keyout certs/server.key \
    -out certs/server.pem -sha256 -days 365 -nodes \
    -subj "/CN=localhost" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "subjectAltName=DNS:spire-identity-exchange.production.other,DNS:spire-identity-exchange-a.production.other,DNS:spire-identity-exchange-b.production.other"
kubectl create secret tls -n spire-server spire-identity-exchange --key=certs/server.key --cert=certs/server.pem

# Install server side a
helm upgrade --install --namespace spire-mgmt --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/spire-values.yaml" \
  --wait --timeout 7m spire-a charts/spire-nested \
  --set tags.bottomTurtleHAA=true \
  --values "${SCRIPTPATH}/spire-identity-exchange-values.yaml" \
  --set "spire-identity-exchange-bottom-turtle-ha-a.enabled=true" \
  --set "global.spire.ingressControllerType=ingress-nginx" \
  "${BROKER_SOCKET_ARGS_A[@]}"

docker exec -i chart-testing-worker /bin/bash -c "more /var/lib/kubelet/pods/*/volumes/kubernetes.io~empty-dir/disk-keymanager/keys.json /var/lib/kubelet/pods/*/volumes/kubernetes.io~empty-dir/spire-agent-persistence/agent-data.json | cat"

# Rollout just to sped up the tests
kubectl patch deployment spiffe-oidc-discovery-provider -n spire-server --type='strategic' -p '{"spec": {"strategy": {"type": "Recreate", "rollingUpdate": null}}}'
kubectl rollout restart daemonset -n spire-system spire-ha-agent
kubectl rollout status daemonset -n spire-system spire-ha-agent --timeout=1m
kubectl rollout restart deployment -n spire-server spiffe-oidc-discovery-provider
kubectl rollout status deployment -n spire-server spiffe-oidc-discovery-provider --timeout=1m
kubectl wait -n spire-server --for=condition=ready pod -l "app.kubernetes.io/name=spiffe-oidc-discovery-provider" --field-selector=status.phase=Running --timeout=90s
curl -k --resolve "oidc-discovery.production.other:443:$IP" "https://oidc-discovery.production.other/.well-known/openid-configuration" -s --fail

# Install server side b
helm upgrade --install --namespace spire-mgmt --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/spire-values.yaml" \
  --wait --timeout 7m spire-b charts/spire-nested \
  --set tags.bottomTurtleHAB=true \
  --set internal-spire-server-bottom-turtle-ha-b.upstreamAuthority.spire.server.port=8082 \
  --values "${SCRIPTPATH}/spire-identity-exchange-values.yaml" \
  --set "spire-identity-exchange-bottom-turtle-ha-b.enabled=true" \
  --set "global.spire.ingressControllerType=ingress-nginx" \
  "${BROKER_SOCKET_ARGS_B[@]}"

if [ "${BROKER}" -eq 1 ]; then
  # Both sides' spire-ha-agent entries must federate with other.invalid before the workload test.
  # The bundle came in with the install, so this should already be true rather than waited on.
  wait_for_entry_federation spire-a-internal-server-0 other.invalid
  wait_for_entry_federation spire-b-internal-server-0 other.invalid
fi

docker ps
docker exec -i chart-testing-worker /bin/bash -c "more /var/lib/kubelet/pods/*/volumes/kubernetes.io~empty-dir/disk-keymanager/keys.json /var/lib/kubelet/pods/*/volumes/kubernetes.io~empty-dir/spire-agent-persistence/agent-data.json | cat"

# From here on out, we sanity check that everything is working properly with both servers running.

ENTRIES="$(kubectl exec -i -n spire-server spire-b-internal-server-0 -- spire-server entry show)"
if [[ "${ENTRIES}" == "Found 0 entries" ]]; then
  echo "${ENTRIES}"
  exit 1
fi

ENTRIES="$(kubectl exec -i -n spire-server spire-a-internal-server-0 -- spire-server entry show)"
if [[ "${ENTRIES}" == "Found 0 entries" ]]; then
  echo "${ENTRIES}"
  exit 1
fi

kubectl get pods -A -o wide
kubectl get ingress -A

helm test --namespace spire-mgmt spire-a
helm test --namespace spire-mgmt spire-b
curl -k --resolve "oidc-discovery.production.other:443:$IP" "https://oidc-discovery.production.other/.well-known/openid-configuration" -s --fail

kubectl apply -f "${SCRIPTPATH}/test-job.yaml"
kubectl wait --for=condition=complete --timeout=60s job/test && \
TOKEN=$(kubectl logs job/test)
curl --fail-with-body -H "Authorization: Bearer ${TOKEN}" -X POST --resolve "spire-identity-exchange-a-rest.production.other:443:$IP" "https://spire-identity-exchange-a-rest.production.other/api/v1/svid/k8s_psat/x509" -k -sS -q
curl --fail-with-body -H "Authorization: Bearer ${TOKEN}" -X POST --resolve "spire-identity-exchange-b-rest.production.other:443:$IP" "https://spire-identity-exchange-b-rest.production.other/api/v1/svid/k8s_psat/x509" -k -sS -q

# Registry image pull. zot serves a SPIRE issued certificate, an in cluster job pushes an
# image with an identity minted by the exchange, and kubelet pulls it back through the
# image credential provider staged on every node by .github/scripts.

# Nodes are not cluster DNS clients, so coredns does nothing for containerd. Give each
# node the name directly, and a hosts.toml so it trusts the registry's SPIRE certificate.
# The bundle has to carry both roots: after a failover the certificate is issued by the
# other side's chain.
sudo spire-server bundle show -socketPath /run/spire/server/sockets/a/private/api.sock | sudo tee /tmp/zot-ca.pem > /dev/null
sudo spire-server bundle show -socketPath /run/spire/server/sockets/b/private/api.sock | sudo tee -a /tmp/zot-ca.pem > /dev/null
for NODE in $(kubectl get nodes -o name | cut -d/ -f2); do
  # The credential provider runs on the node, not in a pod, so it resolves the registry
  # and the exchange here rather than through coredns.
  docker exec -i "${NODE}" /bin/bash -c "grep -q zot.production.other /etc/hosts || echo '$IP zot.production.other spire-identity-exchange-rest-spiffe.production.other' >> /etc/hosts"
  docker exec -i "${NODE}" /bin/bash -c "mkdir -p /etc/containerd/certs.d/zot.production.other"
  docker exec -i "${NODE}" /bin/bash -c "cat > /etc/containerd/certs.d/zot.production.other/zot-ca.pem" < /tmp/zot-ca.pem
  docker exec -i "${NODE}" /bin/bash -c "cat > /etc/containerd/certs.d/zot.production.other/hosts.toml" <<EOF
server = "https://zot.production.other"

[host."https://zot.production.other"]
  capabilities = ["pull", "resolve"]
  ca = "/etc/containerd/certs.d/zot.production.other/zot-ca.pem"
EOF
done

helm upgrade --install zot zot --version "$VERSION_ZOT" --repo "$HELM_REPO_ZOT" \
  --namespace zot --create-namespace \
  --values "${SCRIPTPATH}/zot-values.yaml" \
  --wait --timeout 5m

# Pull the job images out of the charts so they always sync up.
BUSYBOX_IMAGE=$(helm template t charts/spire -s charts/spiffe-oidc-discovery-provider/templates/tests/test-keys.yaml --values "${COMMON_TEST_YOUR_VALUES}" --set spiffe-oidc-discovery-provider.enabled=true | yq e 'select(.kind=="Pod") | .spec.initContainers[] | select(.name=="static-busybox") | .image' -)
AGENT_IMAGE=$(helm template t charts/spire -s charts/spire-agent/templates/daemonset.yaml --values "${COMMON_TEST_YOUR_VALUES}" --set spire-agent.enabled=true | yq e 'select(.kind=="DaemonSet") | .spec.template.spec.containers[] | select(.name=="spire-agent") | .image' -)
TOOLKIT_IMAGE=$(helm template t charts/spire -s charts/spiffe-oidc-discovery-provider/templates/tests/test-keys.yaml --values "${COMMON_TEST_YOUR_VALUES}" --set spiffe-oidc-discovery-provider.enabled=true | yq e 'select(.kind=="Pod") | .spec.containers[] | select(.name=="verify-keys") | .image' -)
echo "image pull job images: ${BUSYBOX_IMAGE} ${AGENT_IMAGE} ${TOOLKIT_IMAGE}"

# Substitute rather than rewrite. yq edits the document structure, which is version
# dependent and on a multi document file can graft fields onto the wrong document; sed
# cannot restructure anything. Writing to a file first also keeps the applied manifest
# inspectable and avoids the pipeline trap, since this script sets -e but not -o pipefail.
apply_registry_job() {
  local rendered
  rendered="/tmp/$(basename "$1")"
  sed -e "s|IMAGE_BUSYBOX|${BUSYBOX_IMAGE}|g" \
      -e "s|IMAGE_SPIRE_AGENT|${AGENT_IMAGE}|g" \
      -e "s|IMAGE_TOOLKIT|${TOOLKIT_IMAGE}|g" \
      "$1" > "${rendered}"
  # Fail loudly rather than applying a half substituted manifest.
  if grep -q 'IMAGE_BUSYBOX\|IMAGE_SPIRE_AGENT\|IMAGE_TOOLKIT' "${rendered}"; then
    echo "unsubstituted image placeholder left in ${rendered}"
    exit 1
  fi
  kubectl apply -f "${rendered}"
}

# Push with the writer identity.
apply_registry_job "${SCRIPTPATH}/image-push-job.yaml"
wait_for_job image-push

# Pull it back. Nothing in the job fetches a credential; kubelet runs the plugin, which is
# the whole point of the test. Show what kubelet was actually configured with first: an
# anonymous pull looks identical whether the plugin is absent or merely failing.
dump_kubelet_all
for NODE in $(kubectl get nodes -o name 2>/dev/null | cut -d/ -f2 | grep -v control-plane); do
  probe_credential_provider "${NODE}"
done

# Pull it back. Nothing in the job fetches a credential; kubelet runs the plugin, which is
# the whole point of the test.
kubectl apply -f "${SCRIPTPATH}/image-pull-job.yaml"
wait_for_job image-pull
# Completing at all is the assertion: zot grants no anonymous access, so the image only
# comes down if kubelet ran the plugin and the exchange minted a token zot accepted. The
# kubelet log line naming the plugin needs -v=4, which is not worth turning on for every
# example, so teardown prints it as a diagnostic rather than asserting on it.
kubectl logs job/image-pull | grep IMAGE-PULL-OK

# The pull identity is read only. This job completes only when zot refuses the write.
apply_registry_job "${SCRIPTPATH}/image-push-denied-job.yaml"
wait_for_job image-push-denied
kubectl logs job/image-push-denied | grep PUSH-DENIED-OK

if [ "${BROKER}" -eq 1 ]; then
  # Verify a workload on the ha-agent socket receives the other.invalid federated trust bundles,
  # x509 and jwt, merged from both sides.
  run_federation_test_job
fi

#Test out running only on side b since we know already only both servers work together, and that only side a works if we made it this far.
helm delete -n spire-mgmt spire-a
kubectl rollout restart daemonset -n spire-system spire-ha-agent
kubectl rollout status daemonset -n spire-system spire-ha-agent
kubectl rollout restart deployment -n spire-server spiffe-oidc-discovery-provider
kubectl rollout status deployment -n spire-server spiffe-oidc-discovery-provider --timeout=5m
curl -k --resolve "oidc-discovery.production.other:443:$IP" "https://oidc-discovery.production.other/.well-known/openid-configuration" -s --fail

if [ "${BROKER}" -eq 1 ]; then
  # Verify the other.invalid federated trust bundles still serve with only side b running.
  run_federation_test_job
fi

# The image pull path has to survive losing a side too. Everything it depends on is HA:
# the node's identity comes from the host spire-ha-agent, and the credential provider
# talks to the combined exchange endpoint rather than either side directly. Delete the
# job first so this is a genuine second pull rather than a cached result.
kubectl delete job image-pull
kubectl apply -f "${SCRIPTPATH}/image-pull-job.yaml"
wait_for_job image-pull
kubectl logs job/image-pull | grep IMAGE-PULL-OK

