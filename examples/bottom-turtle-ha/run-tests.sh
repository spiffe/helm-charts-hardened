#!/usr/bin/env bash

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
  sudo systemctl status spire-server@a
  sudo systemctl status spire-server@b
  sudo systemctl status spire-controller-manager@a
  sudo systemctl status spire-controller-manager@b
  sudo systemctl status spire-agent@a
  sudo systemctl status spire-agent@b
  sudo systemctl status spiffe-socat-unix@k8s-spire-server-a
  sudo systemctl status spiffe-socat-unix@k8s-spire-server-b

  print_helm_releases
  print_spire_workload_status spire-root-server
  print_spire_workload_status spire-server spire-system

  if [[ "$1" -ne 0 ]]; then
    get_namespace_details spire-root-server
    get_namespace_details spire-server spire-system
  fi

  if [ "${CLEANUP}" -eq 1 ]; then
    helm uninstall --namespace spire-server spire 2>/dev/null || true
    kubectl delete ns spire-server 2>/dev/null || true
    kubectl delete ns spire-system 2>/dev/null || true

    helm uninstall --namespace mysql spire-root-server 2>/dev/null || true
    kubectl delete ns spire-root-server 2>/dev/null || true
  fi
}

trap 'EC=$? && trap - SIGTERM && teardown $EC' SIGINT SIGTERM EXIT

"${SCRIPTPATH}/../../.github/scripts/prepare-local-chart-deps.sh"

# List nodes
kubectl get nodes

sudo curl -s -o /etc/apt/sources.list.d/spire-examples.list https://raw.githubusercontent.com/spiffe/spire-examples/refs/heads/main/examples/debs/amd64/spire-examples.list
sudo apt-get update
sudo apt-get install -y spire-common spire-agent spire-server spire-controller-manager spiffe-socat-unix

sudo mkdir -p /etc/spire/server/a/manifests/ /etc/spire/server/b/manifests/
sudo cp "${SCRIPTPATH}/example-manifests/node1-k8s-spire-server.yaml" /etc/spire/server/a/manifests/
sudo cp "${SCRIPTPATH}/example-manifests/node1-k8s-spire-server.yaml" /etc/spire/server/b/manifests/

#FIXME consider adding to upstream package
sudo /bin/bash -c 'echo SPIRE_BIND_PORT=8082 > /etc/spire/server/b.env'
sudo /bin/bash -c 'echo "expandEnvStaticManifests: true" >> /etc/spire/controller-manager/default.conf'
sudo cp /etc/spire/controller-manager/default.conf /etc/spire/controller-manager/b.conf
sudo sed -i 's/bindAddress: .*/bindAddress: 0.0.0.0:9125/; s/healthProbeBindAddress: .*/healthProbeBindAddress: 0.0.0.0:9126/;' /etc/spire/controller-manager/b.conf

#FIXME copy in controller manager config.
sudo systemctl start spire-server@a spire-server@b spire-controller-manager@a spire-controller-manager@b
sudo systemctl status spire-server@a
sudo systemctl status spire-server@b

#FIXME need to wait for spire server to health check ok, with a timeout and controller manager to sync
sleep 10

#FIXME add trust syncing spire-ha domain too.

JOIN_TOKEN_A=$(sudo spire-server token generate -spiffeID spiffe://example.org/agent/node1 -socketPath /run/spire/server/sockets/a/private/api.sock | awk '{print "\""$2"\""}')
JOIN_TOKEN_B=$(sudo spire-server token generate -spiffeID spiffe://example.org/agent/node1 -socketPath /run/spire/server/sockets/b/private/api.sock | awk '{print "\""$2"\""}')

export JOIN_TOKEN_A
export JOIN_TOKEN_B

sudo cp -a /etc/spire/agent/default.conf /etc/spire/agent/a.conf
sudo cp -a /etc/spire/agent/default.conf /etc/spire/agent/b.conf

#FIXME consider making this an env var somehow
sudo sed -i "s/# join_token =.*/join_token = ${JOIN_TOKEN_A}/" /etc/spire/agent/a.conf
sudo sed -i "s/# join_token =.*/join_token = ${JOIN_TOKEN_B}/" /etc/spire/agent/b.conf

#FIXME consider adding to upstream package
sudo sed -i 's/server_port = 8081/server_port = 8082/' /etc/spire/agent/b.conf

sudo more /etc/spire/agent/a.conf /etc/spire/agent/b.conf | cat

sudo systemctl start spire-agent@a spire-agent@b
sudo systemctl start spiffe-socat-unix@k8s-spire-server-a spiffe-socat-unix@k8s-spire-server-b

sudo systemctl status spire-agent@a
sudo systemctl status spire-agent@b

#FIXME need to wait for spire agent to health check ok, with a timeout
sleep 15
sudo spire-agent api fetch jwt -audience test -socketPath /var/run/spiffe/socat/unix/k8s-spire-server-a/public/api.sock
sudo spire-agent api fetch jwt -audience test -socketPath /var/run/spiffe/socat/unix/k8s-spire-server-b/public/api.sock

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

kubectl get configmap -n kube-system coredns -o yaml | grep hosts || kubectl get configmap -n kube-system coredns -o yaml | sed "/ready/a\        hosts {\n           fallthrough\n        }" | kubectl apply -f -
kubectl get configmap -n kube-system coredns -o yaml | grep production.other || kubectl get configmap -n kube-system coredns -o yaml | sed "/hosts/a\           $IP spire-server-a.production.other\n           $IP spire-server-b.production.other\n" | kubectl apply -f -
kubectl rollout restart -n kube-system deployment/coredns
kubectl rollout status -n kube-system -w --timeout=1m deploy/coredns

helm upgrade --install --create-namespace --namespace spire-mgmt --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/spire-values.yaml" \
  --wait spire charts/spire-nested \
  --set tags.haAgentCommont=true \
  --set "global.spire.namespaces.create=true" \
  --set "global.spire.ingressControllerType=ingress-nginx"

helm upgrade --install --create-namespace --namespace spire-mgmt --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/spire-values.yaml" \
  --wait spire-a charts/spire-nested \
  --set tags.bottomTurtleHAA=true \
  --set global.spire.upstreamSpireAddress=spire-server-a.production.other \
  --set "global.spire.ingressControllerType=ingress-nginx"

helm upgrade --install --create-namespace --namespace spire-mgmt --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/spire-values.yaml" \
  --wait spire-b charts/spire-nested \
  --set tags.bottomTurtleHAB=true \
  --set global.spire.upstreamSpireAddress=spire-server-b.production.other \
  --set "global.spire.ingressControllerType=ingress-nginx"

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

helm test --namespace spire-mgmt spire
helm test --namespace spire-mgmt spire-a
helm test --namespace spire-mgmt spire-b
