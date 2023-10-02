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

helm_install=(helm upgrade --install --create-namespace)
ns=spire-server

teardown() {
  helm uninstall --namespace "${ns}" spire 2>/dev/null || true
  kubectl delete ns "${ns}" 2>/dev/null || true
  kubectl delete ns spire-system 2>/dev/null || true
  helm uninstall --namespace cert-manager cert-manager 2>/dev/null || true
  kubectl delete ns cert-manager 2>/dev/null || true
  helm uninstall --namespace ingress-nginx 2>/dev/null || true
  kubectl delete ns ingress-nginx 2>/dev/null || true
}

trap 'trap - SIGTERM && teardown' SIGINT SIGTERM EXIT

kubectl create namespace spire-system 2>/dev/null || true
kubectl label namespace spire-system pod-security.kubernetes.io/enforce=privileged || true
kubectl create namespace "${ns}" 2>/dev/null || true
kubectl label namespace "${ns}" pod-security.kubernetes.io/enforce=restricted || true

"${helm_install[@]}" cert-manager cert-manager --version "$VERSION_CERT_MANAGER" --repo "$HELM_REPO_CERT_MANAGER" \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --wait

kubectl apply -f "${DEPS}/testcert.yaml" -n spire-server

"${helm_install[@]}" ingress-nginx ingress-nginx --version "$VERSION_INGRESS_NGINX" --repo "$HELM_REPO_INGRESS_NGINX" \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.extraArgs.enable-ssl-passthrough=,controller.admissionWebhooks.enabled=false,controller.service.type=ClusterIP \
  --set controller.ingressClassResource.default=true \
 --wait

ip=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o go-template='{{ .spec.clusterIP }}')
echo "$ip" oidc-discovery.production.other

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

"${helm_install[@]}" spire charts/spire \
  --namespace "${ns}" \
  --values "${SCRIPTPATH}/values.yaml" \
  --values "${SCRIPTPATH}/values-export-spiffe-oidc-discovery-provider-ingress-nginx.yaml" \
  --values "${SCRIPTPATH}/values-export-spire-server-ingress-nginx.yaml" \
  --values "${SCRIPTPATH}/values-export-federation-https-web-ingress-nginx.yaml" \
  --values /tmp/dummydns \
  --set spiffe-oidc-discovery-provider.tests.tls.customCA=tls-cert,spire-server.tests.tls.customCA=tls-cert \
  --set spire-agent.server.address=spire-server.production.other,spire-agent.server.port=443 \
  --values "${SCRIPTPATH}/example-your-values.yaml" \
  --wait

helm test --namespace "${ns}" spire

if helm get manifest -n spire-server spire | grep -i example; then
  echo Global settings did not work. Please fix.
  exit 1
fi

print_helm_releases
print_spire_workload_status "${ns}"

if [[ "$1" -ne 0 ]]; then
  get_namespace_details "${ns}"
fi
