spire-values.yaml
```
spire-server:
  nodeAttestor:
    httpChallenge:
      enabled: true
  controllerManager:
    identities:
      clusterSPIFFEIDs:
        default:
          enabled: false
        spiffe-step-ssh-config:
          type: raw
          namespaceSelector:
            matchLabels:
              "kubernetes.io/metadata.name": default
          podSelector:
            matchLabels:
              app: spiffe-step-ssh
              component: config
        spiffe-step-ssh-fetchca:
          type: raw
          namespaceSelector:
            matchLabels:
              "kubernetes.io/metadata.name": default
          podSelector:
            matchLabels:
              app: spiffe-step-ssh
              component: fetchca
          dnsNameTemplates:
          - "spiffe-step-ssh-fetchca.{{ .TrustDomain }}"
```

```shell
helm upgrade --install -n spire-server spire-crds spire-crds --repo https://spiffe.github.io/helm-charts-hardened/ --create-namespace
helm upgrade --install -n spire-server spire spire --repo https://spiffe.github.io/helm-charts-hardened/ -f spire-values.yaml --set global.spire.ingressControllerType=ingress-nginx,spire-server.ingress.enabled=true
```

```shell
helm upgrade --install ingress-nginx ingress-nginx -n ingress-nginx --create-namespace --repo https://kubernetes.github.io/ingress-nginx --set controller.service.type=ClusterIP,controller.service.externalIPs[0]=$(minikube ip) --set controller.watchIngressWithoutClass=true --set controller.extraArgs.enable-ssl-passthrough=
```

```shell
PASSWORD=$(openssl rand -base64 48)
echo "$PASSWORD" > spiffe-step-ssh-password.txt
step ca init --helm --deployment-type=Standalone --name='My CA' --dns spiffe-step-ssh.example.org --ssh --address :8443 --provisioner default --password-file spiffe-step-ssh-password.txt > spiffe-step-ssh-values.yaml
```

ingress-values.yaml
```yaml
step:
  ingress:
    enabled: true
    annotations:
      "nginx.ingress.kubernetes.io/ssl-passthrough": "true"
    hosts:
    - host: spiffe-step-ssh.example.org
      paths:
      - path: /
        pathType: Prefix
fetchca:
  ingress:
    enabled: true
    annotations:
      "nginx.ingress.kubernetes.io/ssl-passthrough": "true"
    hosts:
    - host: spiffe-step-ssh-fetchca.example.org
      paths:
      - path: /
        pathType: Prefix
```

```shell
helm upgrade --install spiffe-step-ssh . --set caPassword=`cat spiffe-step-ssh-password.txt` -f spiffe-step-ssh-values.yaml -f ingress-values.yaml
```
