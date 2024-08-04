spire-values.yaml
```
spire-server:
  controllerManager:
    identities:
      clusterSPIFFEIDs:
        spire-step-ssh-config:
          type: raw
          namespaceSelector:
            matchLabels:
              "kubernetes.io/metadata.name": default
          podSelector:
            matchLabels:
              app: spire-step-ssh
              component: config
        spire-step-ssh-fetchca:
          type: raw
          namespaceSelector:
            matchLabels:
              "kubernetes.io/metadata.name": default
          podSelector:
            matchLabels:
              app: spire-step-ssh
              component: fetchca
          dnsNameTemplates:
          - "spire-step-ssh-fetchca.{{ .TrustDomain }}"
```

```shell
helm upgrade --install spire-crds charts/spire-crds
helm upgrade --install spire charts/spire -f spire-values.yaml
```

```shell
helm upgrade --install ingress-nginx ingress-nginx -n ingress-nginx --create-namespace --repo https://kubernetes.github.io/ingress-nginx --set controller.service.type=ClusterIP,controller.service.externalIPs[0]=$(minikube ip) --set controller.watchIngressWithoutClass=true --set controller.extraArgs.enable-ssl-passthrough=
```

```shell
PASSWORD=$(openssl rand -base64 48)
echo "$PASSWORD" > spire-step-ssh-password.txt
step ca init --helm --deployment-type=Standalone --name='My CA' --dns step-ssh.example.org --ssh --address :8443 --provisioner default --password-file spire-step-ssh-password.txt > spire-step-ssh-values.yaml
```

ingress-values.yaml
```yaml
step:
  ingress:
    enabled: true
    annotations:
      "nginx.ingress.kubernetes.io/ssl-passthrough": "true"
    hosts:
    - host: step-ssh.example.org
      paths:
      - path: /
        pathType: Prefix
fetchca:
  ingress:
    enabled: true
    annotations:
      "nginx.ingress.kubernetes.io/ssl-passthrough": "true"
    hosts:
    - host: spire-step-ssh-fetchca.example.org
      paths:
      - path: /
        pathType: Prefix
```

```shell
helm upgrade --install spire-step-ssh . --set caPassword=`cat spire-step-ssh-password.txt` -f spire-step-ssh-values.yaml -f ingress-values.yaml
```
