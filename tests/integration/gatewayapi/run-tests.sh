#!/usr/bin/env bash

set -xe

# Gateway API integration test. Mirrors tests/integration/production but exposes
# services through the Kubernetes Gateway API (Envoy Gateway) instead of
# ingress-nginx:
#   - spire-server and the federation endpoint use TLS passthrough (TLSRoute)
#   - the OIDC discovery provider uses HTTPS termination at the edge (HTTPRoute)
# Both share port 443 and are disambiguated by SNI via per-service ListenerSets.
#
# The shared Gateway object is created by this harness (see gateway-eg.yaml)
# rather than by the chart, so its data-plane Service ClusterIP is known before
# the chart is installed and the whole thing installs in a single pass.
#
# The released chart has no Gateway API support, so the production `-u`
# upgrade-from-release path is intentionally omitted here.

SCRIPT="$(readlink -f "$0")"
SCRIPTPATH="$(dirname "${SCRIPT}")"
TESTDIR="${SCRIPTPATH}/../../../.github/tests"
DEPS="${TESTDIR}/dependencies"

# shellcheck source=/dev/null
source "${SCRIPTPATH}/../../../.github/scripts/parse-versions.sh"
# shellcheck source=/dev/null
source "${TESTDIR}/common.sh"

"${SCRIPTPATH}/../../../.github/scripts/prepare-local-chart-deps.sh"

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
    helm uninstall --namespace spire-server spire 2>/dev/null || true
    kubectl delete ns spire-server 2>/dev/null || true
    kubectl delete ns spire-system 2>/dev/null || true
    helm uninstall --namespace cert-manager cert-manager 2>/dev/null || true
    kubectl delete ns cert-manager 2>/dev/null || true
    kubectl delete -f "${DEPS}/gateway-eg.yaml" 2>/dev/null || true
    kubectl delete -f "${DEPS}/gatewayclass-eg.yaml" 2>/dev/null || true
    helm uninstall --namespace envoy-gateway-system eg 2>/dev/null || true
    kubectl delete ns envoy-gateway-system 2>/dev/null || true
    # Leave the Gateway API CRDs installed; removing them is unnecessary and
    # would disrupt anything else on a shared cluster.
  fi
}

trap 'EC=$? && trap - SIGTERM && teardown $EC' SIGINT SIGTERM EXIT

kubectl create namespace spire-system 2>/dev/null || true
kubectl label namespace spire-system pod-security.kubernetes.io/enforce=privileged || true
kubectl create namespace spire-server 2>/dev/null || true
kubectl label namespace spire-server pod-security.kubernetes.io/enforce=restricted || true

helm upgrade --install --create-namespace cert-manager cert-manager \
  --version "$VERSION_CERT_MANAGER" --repo "$HELM_REPO_CERT_MANAGER" \
  --namespace cert-manager \
  --set installCRDs=true \
  --wait

kubectl apply -f "${DEPS}/testcert.yaml" -n spire-server

# Install the Envoy Gateway control plane. Its gateway-crds-helm dependency also
# installs the Gateway API CRDs (bundled v1.5.1), including the standard v1
# ListenerSet, TLSRoute and BackendTLSPolicy we rely on — so no separate CRD
# apply is needed. Pin the standard channel explicitly.
helm upgrade --install --create-namespace eg "$HELM_REGISTRY_ENVOY_GATEWAY" \
  --version "$VERSION_ENVOY_GATEWAY" \
  --namespace envoy-gateway-system \
  --set gateway-crds-helm.crds.gatewayAPI.channel=standard \
  --wait

kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available

# GatewayClass (eg) + an EnvoyProxy that forces the data-plane Service to
# ClusterIP so the hostAliases DNS trick works on kind, then the shared Gateway
# object itself. Creating the Gateway here (not in the chart) makes Envoy Gateway
# provision the data-plane Service up front so we can capture its ClusterIP.
kubectl apply -f "${DEPS}/gatewayclass-eg.yaml"
kubectl apply -f "${DEPS}/gateway-eg.yaml"

# Capture the Envoy Gateway data-plane Service ClusterIP. Envoy Gateway labels
# the Service with the owning Gateway (spire in spire-server).
echo "Waiting for the Envoy Gateway data-plane Service to be provisioned..."
ip=""
for _ in $(seq 1 60); do
  ip=$(kubectl -n envoy-gateway-system get svc \
    -l "gateway.envoyproxy.io/owning-gateway-namespace=spire-server,gateway.envoyproxy.io/owning-gateway-name=spire" \
    -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null || true)
  if [[ -n "$ip" && "$ip" != "None" ]]; then
    break
  fi
  sleep 5
done
if [[ -z "$ip" || "$ip" == "None" ]]; then
  echo "Failed to obtain Envoy Gateway data-plane Service ClusterIP"
  exit 1
fi
echo "$ip" spire-server.production.other oidc-discovery.production.other spire-server-federation.production.other

cat > /tmp/dummydns <<EOF
spiffe-oidc-discovery-provider:
  tests:
    hostAliases:
      - ip: "$ip"
        hostnames:
          - "oidc-discovery.production.other"
spire-agent:
  hostAliases:
    - ip: "$ip"
      hostnames:
        - "spire-server.production.other"
spire-server:
  tests:
    hostAliases:
      - ip: "$ip"
        hostnames:
          - "spire-server-federation.production.other"
EOF

# The Gateway (and its data-plane Service) already exist, so the hostnames
# resolve immediately and the chart installs in a single pass.
helm upgrade --install --create-namespace spire charts/spire \
  --namespace spire-server \
  --values "${COMMON_TEST_YOUR_VALUES}" \
  --values "${SCRIPTPATH}/values-expose-spire-server-gateway-api.yaml" \
  --values "${SCRIPTPATH}/values-expose-spiffe-oidc-discovery-provider-gateway-api.yaml" \
  --values "${SCRIPTPATH}/values-expose-federation-https-web-gateway-api.yaml" \
  --values /tmp/dummydns \
  --set spiffe-oidc-discovery-provider.tests.tls.customCA=tls-cert,spire-server.tests.tls.customCA=tls-cert \
  --set spire-agent.server.address=spire-server.production.other,spire-agent.server.port=443 \
  --set spire-server.federation.tls.externalSecret.secretName=tls-cert \
  --wait

helm test --namespace spire-server spire

if helm get manifest -n spire-server spire | grep -i example; then
  echo Global settings did not work. Please fix.
  exit 1
fi
