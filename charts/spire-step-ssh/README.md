```
spire-server:
  controllerManager:
    identities:
      clusterSPIFFEIDs:
        spire-step-ssh-updater:
          type: raw
          namespaceSelector:
            matchLabels:
              "kubernetes.io/metadata.name": default
          podSelector:
            app: spire-step-ssh
            component: config
        spire-step-ssh-server:
          type: raw
          namespaceSelector:
            matchLabels:
              "kubernetes.io/metadata.name": default
          podSelector:
            app: spire-step-ssh
            component: fetchca
          dnsNameTemplates:
          - "spire-step-ssh-fetchca.{{ .TrustDomain }}"
```


```shell
helm upgrade --install ingress-nginx ingress-nginx -n ingress-nginx --create-namespace --repo https://kubernetes.github.io/ingress-nginx --set controller.service.type=ClusterIP,controller.service.externalIPs[0]=$(minikube ip) --set controller.watchIngressWithoutClass=true --set controller.extraArgs.enable-ssl-passthrough=
```

```shell
PASSWORD=$(openssl rand -base64 48)
echo "$PASSWORD" > spire-step-ssh-password.txt
step ca init --helm --deployment-type=Standalone --name='My CA' --dns step-ssh.example.org --ssh --address :8443 --provisioner default --password-file spire-step-ssh-password.txt > spire-step-ssh-values.yaml
```

```shell
helm upgrade --install spire-step-ssh . --set caPassword=`cat /tmp/step/spire-step-ssh-password.txt` -f /tmp/step/spire-step-ssh-values.yaml 
```
