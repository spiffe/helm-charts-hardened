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
  set +e
  openssl s_client -servername spiffe-step-ssh-fetchca.production.other -connect spiffe-step-ssh-fetchca.production.other:443 2>/dev/null </dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p'
  echo spire-agent logs:S
  journalctl -u spire-agent@main
  echo spiffe-step-ssh logs:
  journalctl -u spiffe-step-ssh@main
  echo step pod:
  kubectl logs statefulset/spiffe-step-ssh
  echo fetchca pod:
  kubectl logs deploy/spiffe-step-ssh-fetchca
  echo config pod:
  kubectl logs deploy/spiffe-step-ssh-config
  echo ingress
  kubectl get ingress
  echo describe pods:
  kubectl describe pods
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

echo Network interfaces:
ip a

HIP="$(ip -4 addr show docker0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"

echo "Picked IP ${HIP}"

echo "${HIP} test.production.other" | sudo bash -c 'cat >> /etc/hosts'

sudo adduser spiffe-test
sudo -u spiffe-test mkdir -p /home/spiffe-test/.ssh
sudo chown spiffe-test --recursive /home/spiffe-test
sudo -u spiffe-test ssh-keygen -t ed25519 -f /home/spiffe-test/.ssh/id_ed25519 -q -N ""
sudo -u spiffe-test chmod 600 /home/spiffe-test/.ssh/id_ed25519
sudo -u spiffe-test cp /home/spiffe-test/.ssh/id_ed25519.pub /home/spiffe-test/.ssh/authorized_keys
sudo -u spiffe-test ssh -T -n -i /home/spiffe-test/.ssh/id_ed25519 spiffe-test@test.production.other hostname || echo Expected fail here

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
kubectl get configmap -n kube-system coredns -o yaml | grep test.production.other || kubectl get configmap -n kube-system coredns -o yaml | sed "/hosts/a\           $IP oidc-discovery.production.other\n           $IP spire-server.production.other\n           $HIP test.production.other\n" | kubectl apply -f -
kubectl rollout restart -n kube-system deployment/coredns
kubectl rollout status -n kube-system -w --timeout=1m deploy/coredns

#helm upgrade --install --create-namespace -n spire-system spire-crds charts/spire-crds
helm upgrade --install --create-namespace --namespace spire-mgmt --values "${COMMON_TEST_YOUR_VALUES},${SCRIPTPATH}/root-values.yaml" \
  --wait spire charts/spire-nested \
  --set "global.spire.namespaces.create=true" \
  --set "global.spire.ingressControllerType=ingress-nginx"

kubectl get pods -n spire-server
kubectl exec -it -n spire-server spire-external-server-0 -- spire-server entry create -parentID spiffe://production.other/spire/agent/http_challenge/test.production.other -spiffeID spiffe://production.other/sshd/test.production.other -selector systemd:id:spiffe-step-ssh@main.service

ENTRIES="$(kubectl exec -i -n spire-server spire-external-server-0 -- spire-server entry show)"

if [[ "${ENTRIES}" == "Found 0 entries" ]]; then
  echo "${ENTRIES}"
  exit 1
fi

#helm test --namespace spire-mgmt spire

kubectl get ingress -n spire-server

echo "${IP} spire-server.production.other spiffe-step-ssh.production.other spiffe-step-ssh-fetchca.production.other" | sudo bash -c 'cat >> /etc/hosts'
echo Hosts:
cat /etc/hosts

curl -L https://raw.githubusercontent.com/kfox1111/spire-examples/refs/heads/spiffe-step-ssh/examples/spiffe-step-ssh/scripts/demo.sh | sudo bash

sudo mkdir -p /usr/libexec/spiffe-step-ssh
sudo mkdir -p /etc/systemd/system/sshd.service.d
sudo curl -L -o /usr/libexec/spiffe-step-ssh/update.sh https://raw.githubusercontent.com/kfox1111/spire-examples/refs/heads/spiffe-step-ssh/examples/spiffe-step-ssh/scripts/update.sh
sudo curl -L -o /etc/systemd/system/spiffe-step-ssh@.service https://raw.githubusercontent.com/kfox1111/spire-examples/refs/heads/spiffe-step-ssh/examples/spiffe-step-ssh/systemd/spiffe-step-ssh@.service
sudo curl -L -o /etc/systemd/system/spiffe-step-ssh-cleanup.service https://raw.githubusercontent.com/kfox1111/spire-examples/refs/heads/spiffe-step-ssh/examples/spiffe-step-ssh/systemd/spiffe-step-ssh-cleanup.service
sudo curl -L -o /etc/systemd/system/sshd.service.d/10-spiffe-step-ssh.conf https://raw.githubusercontent.com/kfox1111/spire-examples/refs/heads/spiffe-step-ssh/examples/spiffe-step-ssh/conf/10-spiffe-step-ssh.conf

sudo mkdir -p /etc/spire/agent
sudo cp "${SCRIPTPATH}/spire-agent.conf" /etc/spire/agent/main.conf

PASSWORD=$(openssl rand -base64 48)
echo "$PASSWORD" > spiffe-step-ssh-password.txt
step ca init --helm --deployment-type=Standalone --name='My CA' --dns spiffe-step-ssh.production.other --ssh --address :8443 --provisioner default --password-file spiffe-step-ssh-password.txt > spiffe-step-ssh-values.yaml

# Start things up
sudo systemctl daemon-reload
sudo systemctl enable spire-agent@main
sudo systemctl start spire-agent@main

pushd charts/spiffe-step-ssh
helm dep up
popd

helm upgrade --install spiffe-step-ssh charts/spiffe-step-ssh --set caPassword="$(cat spiffe-step-ssh-password.txt)" -f spiffe-step-ssh-values.yaml -f "${SCRIPTPATH}/ingress-values.yaml" --set trustDomain=production.other --wait --timeout 10m

# Is fetchca responding.
kubectl get configmap -n spire-system spire-bundle-downstream -o go-template='{{ index .data "bundle.crt" }}' > /tmp/ca.pem
cat /tmp/ca.pem
curl https://spiffe-step-ssh-fetchca.production.other -s --cacert /tmp/ca.pem

sudo systemctl start spiffe-step-ssh@main

common_test_file_exists "/var/run/spiffe-step-ssh/ssh_host_rsa_key-cert.pub"

kubectl get configmap spiffe-step-ssh-certs -o 'go-template={{ index .data "ssh_host_ca_key.pub" }}' | sed '/^$/d; s/^/@cert-authority *.production.other /' | sudo -u spiffe-test dd of=/home/spiffe-test/.ssh/known_hosts
sudo -u spiffe-test cat /home/spiffe-test/.ssh/known_hosts

sudo -u spiffe-test ssh -T -n -i /home/spiffe-test/.ssh/id_ed25519 spiffe-test@test.production.other hostname
