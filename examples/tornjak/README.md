# Recommended setup to deploy Tornjak

> [!Warning]
> The current version of Tornjak in this chart is deployed without authentication. Therefore it is not suitable to run this version in production.

## Deploy CRDs

To install Tornjak with the least privileges possible we deploy SPIRE across 2 namespaces.
Create the namespaces explicitly then deploy required CRDs:

```shell
kubectl create namespace "spire-system"
kubectl label namespace "spire-system" pod-security.kubernetes.io/enforce=privileged
kubectl create namespace "spire-server"
kubectl label namespace "spire-server" pod-security.kubernetes.io/enforce=restricted

helm upgrade --install -n spire-server spire-crds charts/spire-crds
```

Or use the temporary namespace for SPIRE deployment:

```shell
helm upgrade --install --create-namespace -n spire-mgmt spire-crds charts/spire-crds
```

## Deploy Tornjak

Before we can deploy Tornjak with SPIRE we need to decide whether the services would be
using direct access, Ingress, or some other method.

### Direct access

This can be done using port-forward. For example, to start Tornjak APIs on port 10000

Deploy SPIRE with Tornjak enabled

```shell
export TORNJAK_API=http://localhost:10000

helm upgrade --install --create-namespace -n spire-mgmt spire charts/spire \
--set global.spire.namespaces.create=true \
--set tornjak-frontend.apiServerURL=$TORNJAK_API \
--values examples/production/example-your-values.yaml \
--values examples/production/values.yaml  \
--values examples/tornjak/values.yaml   \
--render-subchart-notes --debug

# test the Tornjak deployment
helm test spire -n spire-server
```

## Access Tornjak

To access Tornjak you will have to use port-forwarding for the time being *(until we add authentication and ingress)*.

Run following commands from your shell, if you ran with different values your namespace might differ. Consult the install notes printed when running above `helm upgrade` command in that case.

Since `port-forward` is a blocking command, execute them in two different consoles:

```shell
kubectl -n spire-server port-forward service/spire-tornjak-backend 10000:10000
```

```shell
kubectl -n spire-server port-forward service/spire-tornjak-frontend 3000:3000
```

You can now access Tornjak at [localhost:3000](http://localhost:3000).

See [values.yaml](./values.yaml) for more details on the chart configurations to achieve this setup.

## Deploy Tornjak with ingress-nginx

Update examples/production/example-your-values.yaml with your information, most importantly, trustDomain.

```shell
helm upgrade --install --create-namespace -n spire-mgmt spire charts/spire \
--set global.spire.namespaces.create=true \
--values examples/production/values.yaml \
--values examples/tornjak/values.yaml \
--values examples/tornjak/values-ingress.yaml \
--set global.spire.ingressControllerType=ingress-nginx \
--values examples/production/example-your-values.yaml \
--render-subchart-notes --debug
```

## Tornjak and Ingress on Openshift

Obtain the OpenShift Apps Subdomain for Ingress
We will be using the OpenShift application subdomain during our deployment, so let's capture it now and create environment variable by executing the following command:

```shell
export appdomain=$(oc get cm -n openshift-config-managed  console-public -o go-template="{{ .data.consoleURL }}" | sed 's@https://@@; s/^[^.]*\.//')
echo $appdomain
```

We can now use this variable during the installation of the SPIRE Helm charts.

```shell
helm upgrade --install --create-namespace -n spire-mgmt spire charts/spire --set global.spire.namespaces.create=true \
--set global.openshift=true \
--set global.spire.trustDomain=$appdomain \
--set spire-server.ca_subject.common_name=$appdomain \
--set spire-server.ingress.host=spire-server.$appdomain \
--values examples/production/example-my-values.yaml \
--values examples/production/values.yaml  \
--values examples/tornjak/values.yaml   \
--values examples/tornjak/values-ingress.yaml  \
--render-subchart-notes --debug
```

When running on Openshift in some environments like IBM Cloud,
you might need to add the following configurations:

```shell
--values examples/openshift/values-ibm-cloud.yaml
```

## Validation

Confirm  access to the Tornjak API (backend):

```shell
curl https://tornjak-backend.$appdomain
"Welcome to the Tornjak Backend!"
```

If the APIs are accessible, we can verify the Tornjak UI (A React application running in the local browser) can be accessed.
Test access to Tornjak by opening the URL provided in Tornjak-frontend route:

```shell
oc get route -n spire-server -l=app.kubernetes.io/name=tornjak-frontend -o jsonpath='https://{ .items[0].spec.host }'
```

The value should match the following URL:

```shll
echo "https://tornjak-frontend.$appdomain"
```
