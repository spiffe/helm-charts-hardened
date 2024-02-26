# Deploy Tornjak with Auth Enabled

## Install SPIRE CRDs and deploy SPIRE with Tornjak Enabled

To install SPIRE with the least privileges possible we deploy it across 2 namespaces.

1. Install SPIRE CRDs
```shell
helm upgrade --install --create-namespace -n spire-mgmt spire-crds charts/spire-crds
```
1. Deploy SPIRE with Tornjak enabled and provide auth URL to enable auth
```shell
helm upgrade --install \
--set global.spire.namespaces.create=true \
--values examples/production/values.yaml \
--values examples/production/example-your-values.yaml \
--values examples/tornjak/values.yaml \
--values examples/tornjak/values-auth.yaml \
--render-subchart-notes spire charts/spire

# test the Tornjak deployment
helm test spire
```

## Deploy Keycloak
1. Create a secret from the realm JSON file for Tornjak realm import
```shell
kubectl create secret generic realm-secret -n spire-server --from-file=examples/tornjak/keycloak/tornjak-realm.json


1. deploy Keycloak as an auth service
```shell
helm upgrade --install --create-namespace -n spire-server keycloak --values examples/tornjak/keycloak/values.yaml oci://registry-1.docker.io/bitnamicharts/keycloak --render-subchart-notes
```

## Access Tornjak

To access Tornjak use port-forwarding or check the ingress option below.

Run following commands from your shell, if you run with different values your namespace might differ. Consult the install notes printed when running above `helm upgrade` command in that case.

Since `port-forward` is a blocking command, execute them in three different consoles (One for backend, one for frontend and one for auth):

- Backend Service (Terminal 1)
```shell
kubectl -n spire-server port-forward service/spire-tornjak-backend 10000:10000
```
- Frontend Service (Terminal 2)
```shell
kubectl -n spire-server port-forward service/spire-tornjak-frontend 3000:3000
```
- Auth Service [Keycloak] (Terminal 3)
```shell
kubectl -n spire-server port-forward service/keycloak 8080:80
```
You can now access Tornjak at [localhost:3000](http://localhost:3000).

This will redirect to the auth service for authentication [localhost:8080](http://localhost:8080)

See [values.yaml](./values.yaml) for more details on the chart configurations to customize auth config.

## Tornjak and Ingress with ingress-nginx

Update examples/production/example-your-values.yaml with your information, most importantly, trustDomain.

```shell
helm upgrade --install \
--set global.spire.namespaces.create=true \
--set global.spire.ingressControllerType=ingress-nginx \
--values examples/production/values.yaml \
--values examples/production/example-your-values.yaml \
--values examples/tornjak/values.yaml \
--values examples/tornjak/values-auth.yaml \
--values examples/tornjak/values-ingress.yaml \
--render-subchart-notes spire charts/spire
```