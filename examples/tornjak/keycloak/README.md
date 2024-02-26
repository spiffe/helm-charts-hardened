# Deploy Tornjak with Auth Enabled

## Deploy Keycloak (Auth Service)
```shell
# Create a namespace to deploy keycloak and spire-server
kubectl create namespace spire-server
```
```shell
# Create a secret from the realm JSON file for Tornjak realm import
kubectl create secret generic realm-secret -n spire-server --from-file=examples/tornjak/keycloak/tornjak-realm.json
```

```shell
# Deploy Keycloak as an auth service
helm upgrade --install --create-namespace -n spire-server keycloak --values examples/tornjak/keycloak/values.yaml oci://registry-1.docker.io/bitnamicharts/keycloak --render-subchart-notes
```

## Install SPIRE CRDs and deploy SPIRE with Tornjak Enabled

To install SPIRE with the least privileges possible we deploy it across 2 namespaces.

```shell
# Install SPIRE CRDs
helm upgrade --install --create-namespace -n spire-mgmt spire-crds charts/spire-crds
```

```shell
# Deploy SPIRE with Tornjak enabled and provide auth config options to enable auth
helm upgrade --install \
--set global.spire.namespaces.create=true \
--values examples/production/values.yaml \
--values examples/production/example-your-values.yaml \
--values examples/tornjak/values.yaml \
--values examples/tornjak/values-auth.yaml \
--render-subchart-notes spire charts/spire

```

```shell
# Test the Tornjak deployment
helm test spire
```

## Access Tornjak

To access Tornjak use port-forwarding or check the ingress option below.

Run following commands from your shell, if you run with different values your namespace might differ. Consult the install notes printed when running above `helm upgrade` command in that case.

Since `port-forward` is a blocking command, execute them in three different consoles (one for backend, one for frontend and one for auth):

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
Follow the [instructions](../README.md) for installing Tornjak, either locally or in the cloud, with or without Openshift, but add the `--values examples/tornjak/values-auth.yaml` parameter that is referencing Tornjak Authentication values. E.g:

Update examples/production/example-your-values.yaml with your information, most importantly, trustDomain.

```shell
# Deploy SPIRE with Tornjak enabled and auth enabled with ingress config
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