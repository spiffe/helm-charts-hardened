#!/usr/bin/env bash
#
# Exercises jwtSVIDExec kubeConfigs entries in standalone
# controllerManager.deploymentMode end-to-end across two kind clusters:
#
# - The primary ("source") kind cluster created by the outer workflow
#   runs SPIRE with the standalone controller-manager Deployment. Its
#   spiffe-oidc-discovery-provider is exposed via ingress-nginx.
# - A second ("target") kind cluster is created inside this script,
#   with its apiserver configured for SPIFFE-based structured JWT
#   authentication using the source cluster's OIDC discovery URL as
#   the issuer. A ClusterRoleBinding binds the SPIFFE ID minted by
#   jwtSVIDExecConfig.spiffeID to cluster-admin so the standalone CM's
#   requests carry sufficient privilege.
# - The source cluster's standalone controller-manager is then
#   reconfigured with a kubeConfigs.target entry pointing at the
#   target apiserver. The chart wires the exec plugin to source its
#   JWT-SVID from the standalone Pod's own in-pod agent (workload-api
#   mode) and materializes jwtSVIDExecConfig.spiffeID as an extra
#   static bootstrap workload entry parented to the standalone Pod's
#   node-alias.
# - A marker Pod on the target and a ClusterSPIFFEID applied to the
#   target provide the observable: the source SPIRE Server ends up
#   with a reconciled registration entry whose selectors reference
#   the target Pod. That entry only appears if the standalone CM
#   successfully authenticated to the target apiserver using a
#   JWT-SVID minted via its own agent's Workload API.
#
# Note: like the sibling examples/standalone-controller-manager, this
# depends on a spire-controller-manager image build that supports the
# TCP+mTLS spireServerAddress/workloadAPIAddr config fields
# (spiffe/spire-controller-manager#743). Until such a release exists
# and .Values.spire-server.controllerManager.image points at it, this
# example's CI job is expected to fail during the standalone
# Deployment rollout.

set -xe

SCRIPT="$(readlink -f "$0")"
SCRIPTPATH="$(dirname "${SCRIPT}")"
TESTDIR="${SCRIPTPATH}/../../.github/tests"

# shellcheck source=/dev/null
source "${SCRIPTPATH}/../../.github/scripts/parse-versions.sh"
# shellcheck source=/dev/null
source "${TESTDIR}/common.sh"

ns=spire-server
target_kubeconfig="${SCRIPTPATH}/kubeconfig-target"
authn_hostdir="/tmp/standalone-cm-jwt-svid-exec-authn-$$"

CLEANUP=1

for i in "$@"; do
  case $i in
    -c)
      CLEANUP=0
      shift
      ;;
  esac
done

teardown() {
  print_helm_releases
  print_spire_workload_status "${ns}"

  if [[ "$1" -ne 0 ]]; then
    get_namespace_details "${ns}" default
    if [ -f "${target_kubeconfig}" ]; then
      kubectl --kubeconfig "${target_kubeconfig}" get pods -A || true
      kubectl --kubeconfig "${target_kubeconfig}" logs -n kube-system -l component=kube-apiserver --tail=200 || true
    fi
  fi

  if [ "${CLEANUP}" -eq 1 ]; then
    helm uninstall --namespace "${ns}" spire 2>/dev/null || true
    kubectl delete ns "${ns}" 2>/dev/null || true
    kind delete cluster --name target 2>/dev/null || true
    rm -rf "${authn_hostdir}" "${target_kubeconfig}" || true
  fi
}

trap 'EC=$? && trap - SIGTERM && teardown $EC' SIGINT SIGTERM EXIT

"${SCRIPTPATH}/../../.github/scripts/prepare-local-chart-deps.sh"

# ---------------------------------------------------------------------
# Source cluster: SPIRE + ingress-nginx for OIDC discovery reachability.
# ---------------------------------------------------------------------

kubectl get nodes

IP=$(kubectl get nodes chart-testing-control-plane -o go-template='{{ range .status.addresses }}{{ if eq .type "InternalIP" }}{{ .address }}{{ end }}{{ end }}')

helm upgrade --install ingress-nginx ingress-nginx --version "$VERSION_INGRESS_NGINX" --repo "$HELM_REPO_INGRESS_NGINX" \
  --namespace ingress-nginx \
  --create-namespace \
  --set "controller.extraArgs.enable-ssl-passthrough=,controller.admissionWebhooks.enabled=false,controller.service.type=ClusterIP,controller.service.externalIPs[0]=$IP" \
  --set controller.ingressClassResource.default=true \
  --wait

common_test_url "$IP"

# Patch CoreDNS so in-cluster resolution of oidc-discovery.example.org
# reaches the ingress IP. Same pattern used by examples/nested-security.
kubectl get configmap -n kube-system coredns -o yaml | grep hosts \
  || kubectl get configmap -n kube-system coredns -o yaml \
     | sed "/ready/a\        hosts {\n           fallthrough\n        }" \
     | kubectl apply -f -
kubectl get configmap -n kube-system coredns -o yaml | grep example.org \
  || kubectl get configmap -n kube-system coredns -o yaml \
     | sed "/hosts/a\           $IP oidc-discovery.example.org\n" \
     | kubectl apply -f -
kubectl rollout restart -n kube-system deployment/coredns
kubectl rollout status -n kube-system -w --timeout=1m deploy/coredns

kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install --namespace "${ns}" \
  --values "${SCRIPTPATH}/values.yaml" \
  --set "global.spire.ingressControllerType=ingress-nginx" \
  --wait spire charts/spire

kubectl rollout status --watch --timeout 5m --namespace "${ns}" deployment spire-controller-manager-standalone

# ---------------------------------------------------------------------
# Target cluster: kind with structured JWT authn against the source's
# spiffe-oidc-discovery-provider as issuer.
# ---------------------------------------------------------------------

mkdir -p "${authn_hostdir}"
sed "s#__ISSUER_URL__#https://oidc-discovery.example.org#" \
  "${SCRIPTPATH}/.test-files/authentication-config.yaml.tmpl" \
  > "${authn_hostdir}/config.yaml"

target_kind_config="${authn_hostdir}/target-kind-config.yaml"
sed "s#TARGET_AUTHN_HOSTPATH_PLACEHOLDER#${authn_hostdir}#" \
  "${SCRIPTPATH}/.test-files/target-kind-config.yaml.tmpl" \
  > "${target_kind_config}"

kind create cluster --name target --kubeconfig "${target_kubeconfig}" \
  --config "${target_kind_config}" --image "kindest/node:${K8S}"

kubectl --kubeconfig "${target_kubeconfig}" version

# Wait for the target apiserver's structured-authn configuration to be
# effective by probing an unauthenticated liveness endpoint.
count=30
until kubectl --kubeconfig "${target_kubeconfig}" get --raw /livez >/dev/null 2>&1; do
  count=$((count - 1))
  if [ "${count}" -le 0 ]; then
    echo "target apiserver never reported /livez" >&2
    exit 1
  fi
  sleep 2
done

# Patch the target's CoreDNS so its apiserver's OIDC discovery calls
# resolve oidc-discovery.example.org back to the source ingress.
kubectl --kubeconfig "${target_kubeconfig}" get configmap -n kube-system coredns -o yaml | grep hosts \
  || kubectl --kubeconfig "${target_kubeconfig}" get configmap -n kube-system coredns -o yaml \
     | sed "/ready/a\        hosts {\n           fallthrough\n        }" \
     | kubectl --kubeconfig "${target_kubeconfig}" apply -f -
kubectl --kubeconfig "${target_kubeconfig}" get configmap -n kube-system coredns -o yaml | grep example.org \
  || kubectl --kubeconfig "${target_kubeconfig}" get configmap -n kube-system coredns -o yaml \
     | sed "/hosts/a\           $IP oidc-discovery.example.org\n" \
     | kubectl --kubeconfig "${target_kubeconfig}" apply -f -
kubectl --kubeconfig "${target_kubeconfig}" rollout restart -n kube-system deployment/coredns
kubectl --kubeconfig "${target_kubeconfig}" rollout status -n kube-system -w --timeout=1m deploy/coredns

# Install spire-crds on the target so its ClusterSPIFFEID CR can be
# applied there. The standalone CM Deployment for the target cluster
# watches CRs on the target and creates entries in the source SPIRE
# Server over its TCP connection.
helm upgrade --kubeconfig "${target_kubeconfig}" --install \
  --namespace "${ns}" --create-namespace spire-crds charts/spire-crds

kubectl --kubeconfig "${target_kubeconfig}" apply -f "${SCRIPTPATH}/.test-files/target-rbac.yaml"
kubectl --kubeconfig "${target_kubeconfig}" apply -f "${SCRIPTPATH}/target-workload.yaml"
kubectl --kubeconfig "${target_kubeconfig}" apply -f "${SCRIPTPATH}/cluster-spiffe-id.yaml"

# ---------------------------------------------------------------------
# Reconfigure the source SPIRE install with the target kubeConfigs
# entry, then wait for the per-target standalone CM Deployment.
# ---------------------------------------------------------------------

target_apiserver="$(kubectl --kubeconfig "${target_kubeconfig}" config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')"
target_ca_b64="$(kubectl --kubeconfig "${target_kubeconfig}" config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"

helm upgrade --install --namespace "${ns}" \
  --values "${SCRIPTPATH}/values.yaml" \
  --set "global.spire.ingressControllerType=ingress-nginx" \
  --set "spire-server.kubeConfigs.target.jwtSVIDExec.server=${target_apiserver}" \
  --set "spire-server.kubeConfigs.target.jwtSVIDExec.certificateAuthorityData=${target_ca_b64}" \
  --wait spire charts/spire

kubectl rollout status --watch --timeout 5m --namespace "${ns}" deployment spire-controller-manager-standalone-target

# ---------------------------------------------------------------------
# Observable: source SPIRE Server ends up with a registration entry
# reconciled from the target cluster's ClusterSPIFFEID + marker Pod.
# ---------------------------------------------------------------------

count=60
until kubectl exec -n "${ns}" spire-server-0 -c spire-server -- \
        spire-server entry show 2>/dev/null \
        | grep -q "spiffe://example.org/target/ns/target-workload/sa/default"; do
  count=$((count - 1))
  if [ "${count}" -le 0 ]; then
    echo "timed out waiting for the source SPIRE Server to reconcile a registration entry for the target marker Pod" >&2
    kubectl exec -n "${ns}" spire-server-0 -c spire-server -- spire-server entry show || true
    kubectl logs -n "${ns}" deployment/spire-controller-manager-standalone-target --tail=200 || true
    exit 1
  fi
  sleep 2
done

kubectl exec -n "${ns}" spire-server-0 -c spire-server -- spire-server entry show

helm test --namespace "${ns}" spire
