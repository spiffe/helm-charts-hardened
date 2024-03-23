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
curl "$IP"

for cluster in child other; do
  KC="${SCRIPTPATH}/kubeconfig-${cluster}"

  kind create cluster --name "${cluster}" --kubeconfig "${SCRIPTPATH}/kubeconfig-${cluster}" --config "${SCRIPTPATH}/.test-files/${cluster}-kind-config.yaml"
  md5sum "${KC}"
  wc -l "${KC}"

  helm upgrade --kubeconfig "${KC}" --install --create-namespace --namespace spire-mgmt spire-crds charts/spire-crds
  kubectl --kubeconfig "${KC}" apply -f "${SCRIPTPATH}/spire-server-clusterspiffeid.yaml"
  helm upgrade --kubeconfig "${KC}" --install --namespace spire-mgmt --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/child-values.yaml" \
    --set "global.spire.upstreamSpireAddress=spire-server.production.other" \
    --set "global.spire.namespaces.create=true" \
    spire charts/spire-nested
  kubectl --kubeconfig "${KC}" create configmap -n spire-system spire-bundle-upstream

  kubectl get configmap --kubeconfig "${KC}" -n kube-system coredns -o yaml | grep hosts || kubectl get configmap --kubeconfig "${KC}" -n kube-system coredns -o yaml | sed "/ready/a\        hosts {\n           fallthrough\n        }" | kubectl apply --kubeconfig "${KC}" -f -
  kubectl get configmap --kubeconfig "${KC}" -n kube-system coredns -o yaml | grep production.other || kubectl get configmap --kubeconfig "${KC}" -n kube-system coredns -o yaml | sed "/hosts/a\           $IP spire-server.production.other\n           $IP spire-server.production.other\n" | kubectl apply --kubeconfig "${KC}" -f -
  kubectl rollout restart --kubeconfig "${KC}" -n kube-system deployment/coredns
  kubectl rollout status --kubeconfig "${KC}" -n kube-system -w --timeout=1m deploy/coredns
done

CHILD_KCB64="$(base64 < "${SCRIPTPATH}/kubeconfig-child" | tr '\n' ' ' | sed 's/ //g')"
OTHER_KCB64="$(base64 < "${SCRIPTPATH}/kubeconfig-other" | tr '\n' ' ' | sed 's/ //g')"

helm upgrade --install --create-namespace --namespace spire-mgmt --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/root-values.yaml" \
  --wait spire charts/spire-nested \
  --set "spire-server.kubeConfigs.child.kubeConfigBase64=${CHILD_KCB64}" \
  --set "spire-server.kubeConfigs.other.kubeConfigBase64=${OTHER_KCB64}"
helm test --namespace spire-mgmt spire

kubectl --kubeconfig "${SCRIPTPATH}/kubeconfig-child" get configmap -n spire-system spire-bundle-upstream
kubectl --kubeconfig "${SCRIPTPATH}/kubeconfig-other" get configmap -n spire-system spire-bundle-upstream

helm test --kubeconfig "${SCRIPTPATH}/kubeconfig-child" --namespace spire-mgmt spire
helm test --kubeconfig "${SCRIPTPATH}/kubeconfig-other" --namespace spire-mgmt spire

ENTRIES="$(kubectl exec -i -n spire-server spire-server-0 -- spire-server entry show)"

if [[ "${ENTRIES}" == "Found 0 entries" ]]; then
	echo "${ENTRIES}"
	exit 1
fi

