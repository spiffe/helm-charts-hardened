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
  sudo spire-server entry show -socketPath /var/run/spire/server/sockets/a/private/api.sock
  sudo spire-server entry show -socketPath /var/run/spire/server/sockets/b/private/api.sock
  sudo systemctl status spire-controller-manager@a
  sudo systemctl status spire-controller-manager@b
  sudo systemctl status spire-agent@a
  sudo systemctl status spire-agent@b
  sudo systemctl status spire-trust-sync@a
  sudo systemctl status spire-trust-sync@b
  sudo systemctl status spiffe-socat-unix@k8s-spire-server-a
  sudo systemctl status spiffe-socat-unix@k8s-spire-server-b
  sudo systemctl status spiffe-socat-unix@k8s-spire-agent-2-a
  sudo systemctl status spiffe-socat-unix@k8s-spire-agent-2-b
  sudo systemctl status spiffe-socat-unix@k8s-spire-agent-3-a
  sudo systemctl status spiffe-socat-unix@k8s-spire-agent-3-b
  sudo systemctl status spiffe-socat-unix@k8s-spire-agent-4-a
  sudo systemctl status spiffe-socat-unix@k8s-spire-agent-4-b
  sudo spire-server bundle list -socketPath /var/run/spire/server/sockets/a/private/api.sock
  sudo spire-server bundle list -socketPath /var/run/spire/server/sockets/b/private/api.sock
  kubectl exec -i -n spire-server spire-a-internal-server-0 -- spire-server entry show || true
  kubectl exec -i -n spire-server spire-b-internal-server-0 -- spire-server entry show || true

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

"${SCRIPTPATH}/../../.github/scripts/prepare-local-chart-deps.sh"

# List nodes
kubectl get nodes

sudo curl -s -o /etc/apt/sources.list.d/spire-examples.list https://raw.githubusercontent.com/spiffe/spire-examples/refs/heads/main/examples/debs/amd64/spire-examples.list
sudo apt-get update
sudo apt-get install -y spire-common spire-agent spire-server spire-controller-manager spiffe-socat-unix socat spire-trust-sync spiffe-helper

sudo sed -i 's/example.org/production.other/' /etc/spiffe/default-trust-domain.env

sudo mkdir -p /etc/spire/server/a/manifests/ /etc/spire/server/b/manifests/
sudo cp "${SCRIPTPATH}/example-manifests"/* /etc/spire/server/a/manifests/
sudo cp "${SCRIPTPATH}/example-manifests"/* /etc/spire/server/b/manifests/

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

JOIN_TOKEN_A=$(sudo spire-server token generate -spiffeID spiffe://production.other/agent/node1 -socketPath /run/spire/server/sockets/a/private/api.sock | awk '{print "\""$2"\""}')
JOIN_TOKEN_B=$(sudo spire-server token generate -spiffeID spiffe://production.other/agent/node1 -socketPath /run/spire/server/sockets/b/private/api.sock | awk '{print "\""$2"\""}')

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

sudo /bin/bash -c 'echo "SPIRE_SERVER_SOCKET=/var/run/spire/server/sockets/b/private/api.sock" > /etc/spire/trust-sync/a.conf'
sudo /bin/bash -c 'echo "SPIRE_SERVER_SOCKET=/var/run/spire/server/sockets/a/private/api.sock" > /etc/spire/trust-sync/b.conf'

sudo systemctl start spire-agent@a spire-agent@b
sudo systemctl start spire-trust-sync@a spire-trust-sync@b
sudo systemctl start spiffe-socat-unix@k8s-spire-server-a spiffe-socat-unix@k8s-spire-server-b

#Start up node agents. We only have one vm mapped to multiple k8s virtual nodes in kind, so we run a pair per k8s virtual node. Normally you would only run one pair per host/vm.
sudo /bin/bash -c "echo SPIFFE_INSTANCE=a > /etc/spiffe//socat/unix/k8s-spire-agent-2-a.conf"
sudo /bin/bash -c "echo SPIFFE_INSTANCE=a > /etc/spiffe//socat/unix/k8s-spire-agent-3-a.conf"
sudo /bin/bash -c "echo SPIFFE_INSTANCE=a > /etc/spiffe//socat/unix/k8s-spire-agent-4-a.conf"
sudo /bin/bash -c "echo SPIFFE_INSTANCE=b > /etc/spiffe//socat/unix/k8s-spire-agent-2-b.conf"
sudo /bin/bash -c "echo SPIFFE_INSTANCE=b > /etc/spiffe//socat/unix/k8s-spire-agent-3-b.conf"
sudo /bin/bash -c "echo SPIFFE_INSTANCE=b > /etc/spiffe//socat/unix/k8s-spire-agent-4-b.conf"
sudo systemctl start spiffe-socat-unix@k8s-spire-agent-2-a spiffe-socat-unix@k8s-spire-agent-2-b
sudo systemctl start spiffe-socat-unix@k8s-spire-agent-3-a spiffe-socat-unix@k8s-spire-agent-3-b
sudo systemctl start spiffe-socat-unix@k8s-spire-agent-4-a spiffe-socat-unix@k8s-spire-agent-4-b

#FIXME need to wait for spire agent to health check ok, with a timeout
sleep 15
sudo spire-agent api fetch jwt -audience test -socketPath /var/run/spiffe/socat/unix/k8s-spire-server-a/public/spire-agent.sock
sudo spire-agent api fetch jwt -audience test -socketPath /var/run/spiffe/socat/unix/k8s-spire-server-b/public/spire-agent.sock

sudo spire-agent api fetch jwt -audience test -socketPath /var/run/spiffe/socat/unix/k8s-spire-agent-2-a/public/api.sock
sudo spire-agent api fetch jwt -audience test -socketPath /var/run/spiffe/socat/unix/k8s-spire-agent-2-b/public/api.sock
sudo spire-agent api fetch jwt -audience test -socketPath /var/run/spiffe/socat/unix/k8s-spire-agent-3-a/public/api.sock
sudo spire-agent api fetch jwt -audience test -socketPath /var/run/spiffe/socat/unix/k8s-spire-agent-3-b/public/api.sock
sudo spire-agent api fetch jwt -audience test -socketPath /var/run/spiffe/socat/unix/k8s-spire-agent-4-a/public/api.sock
sudo spire-agent api fetch jwt -audience test -socketPath /var/run/spiffe/socat/unix/k8s-spire-agent-4-b/public/api.sock

docker ps
docker exec -it chart-testing-worker ls /var/run/spiffe/socat/unix/k8s-spire-agent-a/public
docker exec -it chart-testing-worker ls /var/run/spiffe/socat/unix/k8s-spire-agent-a/public

kubectl get nodes -o go-template='{{range .items}}{{printf "%s %s\n" .metadata.uid .metadata.name }}{{end}}'

#FIXME temporary until spire-controller-manager gains dynamic node registration support
cat > test-a-values.yaml <<EOF
internal-spire-server-bottom-turtle-ha-a:
  controllerManager:
    identities:
      clusterStaticEntries:
        node1:
          parentID: spiffe://production.other/spire/server
          spiffeID: spiffe://production.other/k8s_psat/production/$(kubectl get node chart-testing-worker -o go-template="{{ .metadata.uid }}")
          selectors:
          - x509pop:san:spire-exchange:node1.production.other
        node2:
          parentID: spiffe://production.other/spire/server
          spiffeID: spiffe://production.other/k8s_psat/production/$(kubectl get node chart-testing-worker2 -o go-template="{{ .metadata.uid }}")
          selectors:
          - x509pop:san:spire-exchange:node2.production.other
        node3:
          parentID: spiffe://production.other/spire/server
          spiffeID: spiffe://production.other/k8s_psat/production/$(kubectl get node chart-testing-worker3 -o go-template="{{ .metadata.uid }}")
          selectors:
          - x509pop:san:spire-exchange:node3.production.other
EOF

sed 's/internal-spire-server-bottom-turtle-ha-a/internal-spire-server-bottom-turtle-ha-b/' test-a-values.yaml > test-b-values.yaml

more test-a-values.yaml | cat
more test-b-values.yaml | cat

#FIXME add some bits to check on spire-ha trust domain

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

HOSTIP=$(ip addr show docker0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)

kubectl get configmap -n kube-system coredns -o yaml | grep hosts || kubectl get configmap -n kube-system coredns -o yaml | sed "/ready/a\        hosts {\n           fallthrough\n        }" | kubectl apply -f -
kubectl get configmap -n kube-system coredns -o yaml | grep production.other || kubectl get configmap -n kube-system coredns -o yaml | sed "/hosts/a\           $HOSTIP spire-server-a.production.other\n           $HOSTIP spire-server-b.production.other\n" | kubectl apply -f -
kubectl rollout restart -n kube-system deployment/coredns
kubectl rollout status -n kube-system -w --timeout=1m deploy/coredns

#FIXME remove nightly once 1.15 is released
helm upgrade --install --create-namespace --namespace spire-mgmt --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/spire-values.yaml" \
  --wait spire charts/spire-nested \
  --set tags.haAgentCommont=true \
  --set "global.spire.namespaces.create=true" \
  --set "downstream-spire-agent-bottom-turtle-ha-a.image.tag=nightly" \
  --set "global.spire.ingressControllerType=ingress-nginx"

#FIXME see if we can tweak upstreamSpireAddress's in the chart rather then use a global.
helm upgrade --install --namespace spire-mgmt --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/spire-values.yaml" \
  --wait spire-a charts/spire-nested \
  --set tags.bottomTurtleHAA=true \
  --set global.spire.upstreamSpireAddress=spire-server-a.production.other \
  --set "downstream-spire-agent-bottom-turtle-ha-a.image.tag=nightly" \
  --set "global.spire.ingressControllerType=ingress-nginx" \
  -f test-a-values.yaml

helm upgrade --install --namespace spire-mgmt --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/spire-values.yaml" \
  --wait spire-b charts/spire-nested \
  --set tags.bottomTurtleHAB=true \
  --set global.spire.upstreamSpireAddress=spire-server-b.production.other \
  --set internal-spire-server-bottom-turtle-ha-b.upstreamAuthority.spire.server.port=8082 \
  --set "downstream-spire-agent-bottom-turtle-ha-a.image.tag=nightly" \
  --set "global.spire.ingressControllerType=ingress-nginx" \
  -f test-b-values.yaml

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

#FIXME automate the check.
kubectl exec -i -n spire-server spire-a-internal-server-0 -- spire-server bundle list
kubectl exec -i -n spire-server spire-b-internal-server-0 -- spire-server bundle list

kubectl get pods -A

helm test --namespace spire-mgmt spire
helm test --namespace spire-mgmt spire-a
helm test --namespace spire-mgmt spire-b
