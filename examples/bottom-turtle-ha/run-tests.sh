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

if [ "$GITLAB_CI" = "true" ]; then
  echo "Running in GitLab CI"
else
  echo "Do not run this script on your own box. For testing, it deploys a testing local spire ha setup using sudo. This is likely not what you want. Only use this script as a reference."
  exit 1
fi

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

"${SCRIPTPATH}/../../.github/scripts/prepare-local-chart-deps.sh"

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
