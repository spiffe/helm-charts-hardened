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

#helm upgrade --install --create-namespace spire charts/spire \
#  --namespace spire-root-server \
#  --values "${DEPS}/spire-root-server-values.yaml" \
#  --wait

kind create cluster --name child --kubeconfig "${SCRIPTPATH}/kubeconfig-child" --config "${SCRIPTPATH}/child-kind-config.yaml"
md5sum "${SCRIPTPATH}/kubeconfig-child"
wc -l "${SCRIPTPATH}/kubeconfig-child"
CHILD_KCB64="$(base64 < "${SCRIPTPATH}/kubeconfig-child" | tr '\n' ' ' | sed 's/ //g')"

helm upgrade --kubeconfig "${SCRIPTPATH}/kubeconfig-child" --install --create-namespace --namespace spire-mgmt spire-crds charts/spire-crds
kubectl --kubeconfig "${SCRIPTPATH}/kubeconfig-child" apply -f "${SCRIPTPATH}/sodp-clusterspiffeid.yaml"
helm upgrade --kubeconfig "${SCRIPTPATH}/kubeconfig-child" --install --namespace spire-mgmt --values "${SCRIPTPATH}/child-values.yaml" \
  spire charts/spire
kubectl --kubeconfig "${SCRIPTPATH}/kubeconfig-child" create configmap -n spire-system spire-bundle-upstream

kind create cluster --name other --kubeconfig "${SCRIPTPATH}/kubeconfig-other" --config "${SCRIPTPATH}/other-kind-config.yaml"
md5sum "${SCRIPTPATH}/kubeconfig-other"
wc -l "${SCRIPTPATH}/kubeconfig-other"
OTHER_KCB64="$(base64 < "${SCRIPTPATH}/kubeconfig-other" | tr '\n' ' ' | sed 's/ //g')"

helm upgrade --kubeconfig "${SCRIPTPATH}/kubeconfig-other" --install --create-namespace --namespace spire-mgmt spire-crds charts/spire-crds
kubectl --kubeconfig "${SCRIPTPATH}/kubeconfig-other" apply -f "${SCRIPTPATH}/sodp-clusterspiffeid.yaml"
helm upgrade --kubeconfig "${SCRIPTPATH}/kubeconfig-other" --install --namespace spire-mgmt --values "${SCRIPTPATH}/child-values.yaml" \
  spire charts/spire
kubectl --kubeconfig "${SCRIPTPATH}/kubeconfig-other" create configmap -n spire-system spire-bundle-upstream

helm upgrade --install --create-namespace --namespace spire-mgmt --values "${SCRIPTPATH}/values.yaml" \
  --wait spire charts/spire \
  --set "spire-server.kubeConfigs.child.kubeConfigBase64=${CHILD_KCB64}" \
  --set "spire-server.kubeConfigs.other.kubeConfigBase64=${OTHER_KCB64}"
helm test --namespace spire-mgmt spire
kubectl --kubeconfig "${SCRIPTPATH}/kubeconfig-child" get configmap -n spire-system spire-bundle-upstream
kubectl --kubeconfig "${SCRIPTPATH}/kubeconfig-other" get configmap -n spire-system spire-bundle-upstream

CHILD_ENTRIES="$(kubectl exec -i -n spire-server spire-server-0 -- spire-server entry show)"

if [[ "${CHILD_ENTRIES}" == "Found 0 entries" ]]; then
	echo "${CHILD_ENTRIES}"
	exit 1
fi

OTHER_ENTRIES="$(kubectl exec -i -n spire-server spire-server-0 -- spire-server entry show)"

if [[ "${OTHER_ENTRIES}" == "Found 0 entries" ]]; then
	echo "${OTHER_ENTRIES}"
	exit 1
fi
