#!/usr/bin/env bash

set -xe

SCRIPT="$(readlink -f "$0")"
SCRIPTPATH="$(dirname "${SCRIPT}")"
TESTDIR="${SCRIPTPATH}/../../.github/tests"
DEPS="${TESTDIR}/dependencies"

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
  print_spire_workload_status spire-server spire-system

  if [[ "$1" -ne 0 ]]; then
    get_namespace_details spire-server spire-system
  fi

  if [ "${CLEANUP}" -eq 1 ]; then
    helm uninstall --namespace spire-mgmt spire-b 2>/dev/null || true
    helm uninstall --namespace spire-mgmt spire-a 2>/dev/null || true
    kubectl delete ns spire-mgmt 2>/dev/null || true
  fi
}

trap 'EC=$? && trap - SIGTERM && teardown $EC' SIGINT SIGTERM EXIT

helm upgrade --install ingress-nginx ingress-nginx --version "$VERSION_INGRESS_NGINX" --repo "$HELM_REPO_INGRESS_NGINX" \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.extraArgs.enable-ssl-passthrough=,controller.admissionWebhooks.enabled=false,controller.service.type=ClusterIP \
  --set controller.ingressClassResource.default=true \
  --wait

IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o yaml | yq e .spec.clusterIPs[0] -)
kubectl get configmap -n kube-system coredns -o yaml | grep hosts || kubectl get configmap -n kube-system coredns -o yaml | sed "/ready/a\        hosts {\n           fallthrough\n        }" | kubectl apply -f -
kubectl get configmap -n kube-system coredns -o yaml | grep a-org || kubectl get configmap -n kube-system coredns -o yaml | sed "/hosts/a\           $IP spire-server-federation.a-org.local\n           $IP spire-server-federation.b-org.local\n" | kubectl apply -f -

kubectl rollout restart -n kube-system deployment/coredns
kubectl rollout status -w --timeout=1m deploy/coredns -n kube-system

kubectl create namespace spire-mgmt --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace spire-mgmt pod-security.kubernetes.io/enforce=restricted || true

helm upgrade --install --namespace spire-mgmt --values "${SCRIPTPATH}/a-values.yaml" \
  --wait spire-a charts/spire

helm upgrade --install --namespace spire-mgmt --values "${SCRIPTPATH}/b-values.yaml" \
  --wait spire-b charts/spire

kubectl exec -it -n spire-server spire-a-server-0 -c spire-server -- spire-server bundle show -format spiffe | kubectl exec -i -n spire-server spire-b-server-0 -c spire-server -- spire-server bundle set -format spiffe -id spiffe://a-org.local
kubectl exec -it -n spire-server spire-b-server-0 -c spire-server -- spire-server bundle show -format spiffe | kubectl exec -i -n spire-server spire-a-server-0 -c spire-server -- spire-server bundle set -format spiffe -id spiffe://b-org.local

kubectl exec -it -n spire-server spire-b-server-0 -c spire-server -- spire-server bundle list
kubectl exec -it -n spire-server spire-a-server-0 -c spire-server -- spire-server bundle list

kubectl apply -f "${SCRIPTPATH}/server-svc.yaml"
kubectl apply -f "${SCRIPTPATH}/server-pod.yaml"
kubectl apply -f "${SCRIPTPATH}/client-pod.yaml"

kubectl wait --for=condition=Ready pod/client --timeout 5m
