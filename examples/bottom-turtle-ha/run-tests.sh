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

for i in "$@"; do
  case $i in
    -c)
      CLEANUP=0
      shift # past argument=value
      ;;
  esac
done

if [ "x${GITHUB_JOB}" != "x" ]; then
  echo "Running in GitHub"
else
  echo "Do not run this script on your own box. For testing, it deploys a testing local spire ha setup using sudo. This is likely not what you want. Only use this script as a reference."
  exit 1
fi

teardown() {
  echo ---------------------------
  sudo systemctl status spire-server@a || true
  sudo systemctl status spire-server@b || true
  sudo spire-server entry show -socketPath /var/run/spire/server/sockets/a/private/api.sock || true
  sudo spire-server entry show -socketPath /var/run/spire/server/sockets/b/private/api.sock || true
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

  print_helm_releases

  if [[ "$1" -ne 0 ]]; then
    get_namespace_details spire-server spire-system
    kubectl describe pod -n spire-system
  fi

  if [ "${CLEANUP}" -eq 1 ]; then
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

"${SCRIPTPATH}/../../.github/scripts/prepare-local-chart-deps.sh"

# Get the package repo and install the packages
sudo curl -s -o /etc/apt/sources.list.d/spire-examples.list https://raw.githubusercontent.com/spiffe/spire-examples/refs/heads/main/examples/debs/amd64/spire-examples.list
sudo apt-get update
sudo apt-get install -y spire-common spire-agent spire-server spire-controller-manager spiffe-socat-unix socat spire-trust-sync spiffe-helper

# Set our testing trust domain
sudo sed -i 's/example.org/production.other/' /etc/spiffe/default-trust-domain.env

# register some workloads with the spire server using manifests
sudo mkdir -p /etc/spire/server/a/manifests/ /etc/spire/server/b/manifests/
sudo cp "${SCRIPTPATH}/example-manifests"/* /etc/spire/server/a/manifests/
sudo cp "${SCRIPTPATH}/example-manifests"/* /etc/spire/server/b/manifests/

# For testing, help speed up the sync
sudo rm -f /etc/spire/server/a/manifests/node1-k8s-spire-server.yaml
sudo rm -f /etc/spire/server/b/manifests/node1-k8s-spire-server.yaml

# Since we are running the two root spire servers on the same machine, we need to ensure ports do not conflict for server b
sudo /bin/bash -c 'echo SPIRE_BIND_PORT=8082 > /etc/spire/server/b.env'
sudo cp /etc/spire/controller-manager/default.conf /etc/spire/controller-manager/b.conf
#FIXME consider making bind address overridable via port like above
sudo sed -i 's/bindAddress: .*/bindAddress: 0.0.0.0:9125/; s/healthProbeBindAddress: .*/healthProbeBindAddress: 0.0.0.0:9126/;' /etc/spire/controller-manager/b.conf

#FIXME consider adding to upstream package
sudo /bin/bash -c 'echo "expandEnvStaticManifests: true" >> /etc/spire/controller-manager/default.conf'
sudo /bin/bash -c 'echo "expandEnvStaticManifests: true" >> /etc/spire/controller-manager/b.conf'

# Startup servers and make sure they are ready
sudo systemctl start spire-server@a spire-server@b spire-controller-manager@a spire-controller-manager@b
wait_for_healthcheck spire-server /run/spire/server/sockets/a/private/api.sock
wait_for_healthcheck spire-server /run/spire/server/sockets/b/private/api.sock

# Configure our agents. For the test, create join tokens for both agents. You should really use a node attestor other then join tokens such as tpm-direct, http_challenge, or a cloud provider one
JOIN_TOKEN_A=$(sudo spire-server token generate -spiffeID spiffe://production.other/agent/node1 -socketPath /run/spire/server/sockets/a/private/api.sock | awk '{print "\""$2"\""}')
JOIN_TOKEN_B=$(sudo spire-server token generate -spiffeID spiffe://production.other/agent/node1 -socketPath /run/spire/server/sockets/b/private/api.sock | awk '{print "\""$2"\""}')
export JOIN_TOKEN_A
export JOIN_TOKEN_B
sudo cp -a /etc/spire/agent/default.conf /etc/spire/agent/a.conf
sudo cp -a /etc/spire/agent/default.conf /etc/spire/agent/b.conf
#FIXME consider making this an env var somehow
sudo sed -i "s/# join_token =.*/join_token = ${JOIN_TOKEN_A}/" /etc/spire/agent/a.conf
sudo sed -i "s/# join_token =.*/join_token = ${JOIN_TOKEN_B}/" /etc/spire/agent/b.conf
#FIXME consider making this an env var somehow
sudo sed -i 's/server_port = 8081/server_port = 8082/' /etc/spire/agent/b.conf

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

#FIXME disk writer in agent with emptydir

#FIXME temporary until spire-controller-manager gains dynamic node registration support
cat > test-a-values.yaml <<EOF
internal-spire-server-bottom-turtle-ha-a:
  controllerManager:
    identities:
      clusterStaticEntries:
        node2:
          parentID: spiffe://production.other/spire/server
          spiffeID: spiffe://production.other/k8s_psat/production/$(kubectl get node chart-testing-worker -o go-template="{{ .metadata.uid }}")
          selectors:
          - spiffe_id:spiffe://production.other/spire/agent/x509pop/node2.production.other
        node3:
          parentID: spiffe://production.other/spire/server
          spiffeID: spiffe://production.other/k8s_psat/production/$(kubectl get node chart-testing-worker2 -o go-template="{{ .metadata.uid }}")
          selectors:
          - spiffe_id:spiffe://production.other/spire/agent/x509pop/node3.production.other
        node4:
          parentID: spiffe://production.other/spire/server
          spiffeID: spiffe://production.other/k8s_psat/production/$(kubectl get node chart-testing-worker3 -o go-template="{{ .metadata.uid }}")
          selectors:
          - spiffe_id:spiffe://production.other/spire/agent/x509pop/node4.production.other
EOF
sed 's/internal-spire-server-bottom-turtle-ha-a/internal-spire-server-bottom-turtle-ha-b/' test-a-values.yaml > test-b-values.yaml

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
kubectl get configmap -n kube-system coredns -o yaml | grep production.other || kubectl get configmap -n kube-system coredns -o yaml | sed "/hosts/a\           $HOSTIP spire-server-a.production.other\n           $HOSTIP oidc-discovery.production.other\n           $HOSTIP spire-server-b.production.other\n" | kubectl apply -f -
kubectl rollout restart -n kube-system deployment/coredns
kubectl rollout status -n kube-system -w --timeout=1m deploy/coredns

#FIXME remove nightly once 1.15 is released

#FIXME see if we can tweak upstreamSpireAddress's in the chart rather then use a global.
# Install the common components
helm upgrade --install --create-namespace --namespace spire-mgmt --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/spire-values.yaml" \
  spire charts/spire-nested \
  --set tags.haAgentCommon=true \
  --set "global.spire.namespaces.create=true" \
  --set "global.spire.ingressControllerType=ingress-nginx" \
  --set "spiffe-oidc-discovery-provider.ingress.enabled=true"

# Install server side a
helm upgrade --install --namespace spire-mgmt --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/spire-values.yaml" \
  --wait spire-a charts/spire-nested \
  --set tags.bottomTurtleHAA=true \
  --set global.spire.upstreamSpireAddress=spire-server-a.production.other \
  --set "internal-spire-server-bottom-turtle-ha-a.image.tag=nightly" \
  --set "downstream-spire-agent-bottom-turtle-ha-a.image.tag=nightly" \
  --set "global.spire.ingressControllerType=ingress-nginx" \
  -f test-a-values.yaml

# Rollout just to sped up the tests
kubectl patch deployment spiffe-oidc-discovery-provider -n spire-server --type='strategic' -p '{"spec": {"strategy": {"type": "Recreate", "rollingUpdate": null}}}'
kubectl rollout restart daemonset -n spire-system spire-ha-agent
kubectl rollout status daemonset -n spire-system spire-ha-agent
kubectl rollout restart deployment -n spire-server spiffe-oidc-discovery-provider
kubectl rollout status deployment -n spire-server spiffe-oidc-discovery-provider --timeout=1m
kubectl wait -n spire-server --for=condition=ready pod -l "app.kubernetes.io/name=spiffe-oidc-discovery-provider" --field-selector=status.phase=Running --timeout=90s
curl -k --resolve "oidc-discovery.production.other:443:$IP" "https://oidc-discovery.production.other/.well-known/openid-configuration" -s --fail

# Install server side b
helm upgrade --install --namespace spire-mgmt --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/spire-values.yaml" \
  --wait spire-b charts/spire-nested \
  --set tags.bottomTurtleHAB=true \
  --set global.spire.upstreamSpireAddress=spire-server-b.production.other \
  --set internal-spire-server-bottom-turtle-ha-b.upstreamAuthority.spire.server.port=8082 \
  --set "internal-spire-server-bottom-turtle-ha-b.image.tag=nightly" \
  --set "downstream-spire-agent-bottom-turtle-ha-b.image.tag=nightly" \
  --set "global.spire.ingressControllerType=ingress-nginx" \
  -f test-b-values.yaml

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

helm test --namespace spire-mgmt spire-a
helm test --namespace spire-mgmt spire-b
curl -k --resolve "oidc-discovery.production.other:443:$IP" "https://oidc-discovery.production.other/.well-known/openid-configuration" -s --fail

#Test out running only on side b since we know already only both servers work together, and that only side a works if we made it this far.
helm delete -n spire-mgmt spire-a
kubectl rollout restart daemonset -n spire-system spire-ha-agent
kubectl rollout status daemonset -n spire-system spire-ha-agent
kubectl rollout restart deployment -n spire-server spiffe-oidc-discovery-provider
kubectl rollout status deployment -n spire-server spiffe-oidc-discovery-provider --timeout=1m
curl -k --resolve "oidc-discovery.production.other:443:$IP" "https://oidc-discovery.production.other/.well-known/openid-configuration" -s --fail

