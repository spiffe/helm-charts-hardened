#!/usr/bin/env bash

set -xe

SCRIPT="$(readlink -f "$0")"
SCRIPTPATH="$(dirname "${SCRIPT}")"
TESTDIR="${SCRIPTPATH}/../../../.github/tests"
#DEPS="${TESTDIR}/dependencies"

# shellcheck source=/dev/null
source "${SCRIPTPATH}/../../../.github/scripts/parse-versions.sh"
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

teardown() {
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

# Update deps
helm dep up charts/spire-nested

# List nodes
kubectl get nodes

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
kubectl get configmap -n kube-system coredns -o yaml | grep test.production.other || kubectl get configmap -n kube-system coredns -o yaml | sed "/hosts/a\           $IP test.production.other\n" | kubectl apply -f -
kubectl rollout restart -n kube-system deployment/coredns
kubectl rollout status -n kube-system -w --timeout=1m deploy/coredns

#helm upgrade --install --create-namespace -n spire-system spire-crds charts/spire-crds
helm upgrade --install --create-namespace --namespace spire-mgmt --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/root-values.yaml" \
  --wait spire charts/spire-nested \
  --set "global.spire.namespaces.create=true" \
  --set "global.spire.ingressControllerType=ingress-nginx"

kubectl get pods -n spire-server
kubectl exec -it -n spire-server spire-external-server-0 -- spire-server entry create -parentID spiffe://production.other/spire/agent/http_challenge/test.production.other -spiffeID spiffe://production.other/sshd/test.production.other -selector systemd:id:spiffe-step-ssh.service

ENTRIES="$(kubectl exec -i -n spire-server spire-external-server-0 -- spire-server entry show)"

if [[ "${ENTRIES}" == "Found 0 entries" ]]; then
  echo "${ENTRIES}"
  exit 1
fi

helm test --namespace spire-mgmt spire

kubectl get ingress -n spire-server

echo Hosts:
cat /etc/hosts

curl -L https://raw.githubusercontent.com/kfox1111/spire-examples/refs/heads/spiffe-step-ssh/examples/spiffe-step-ssh/scripts/demo.sh | bash

mkdir -p /usr/libexec/spiffe-step-ssh
curl -L -o /usr/libexec/spiffe-step-ssh/update.sh https://raw.githubusercontent.com/kfox1111/spire-examples/refs/heads/spiffe-step-ssh/examples/spiffe-step-ssh/scripts/update.sh
curl -L -o /usr/libexec/spiffe-step-ssh/helper.conf https://raw.githubusercontent.com/kfox1111/spire-examples/refs/heads/spiffe-step-ssh/examples/spiffe-step-ssh/conf/helper.conf
curl -L -o /etc/systemd/system/spiffe-step-ssh.service https://raw.githubusercontent.com/kfox1111/spire-examples/refs/heads/spiffe-step-ssh/examples/spiffe-step-ssh/systemd/spiffe-step-ssh.service

# Start things up
systemctl daemon-reload
systemctl enable spire-agent@main
systemctl start spire-agent@main
systemctl enable spiffe-step-ssh
systemctl start spiffe-step-ssh
