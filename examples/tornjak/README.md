# Recommended setup to deploy Tornjak

To install Spire with the least privileges possible we deploy spire across 2 namespaces.

```shell
kubectl create namespace "spire-system"
kubectl label namespace "spire-system" pod-security.kubernetes.io/enforce=privileged
kubectl create namespace "spire-server"
kubectl label namespace "spire-server" pod-security.kubernetes.io/enforce=restricted

# deploy SPIRE with Tornjak enabled
helm upgrade --install --namespace spire-server spire charts/spire \
--values tests/integration/psat/values.yaml \
--values examples/tornjak/values.yaml \
--values your-values.yaml \
--render-subchart-notes

# test the Tornjak deployment
helm test spire -n spire-server
```

### Access Tornjak directly

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

Update your-values.yaml with your information, most importantly, trustDomain, and redeploy.

```shell
helm upgrade --install --namespace spire-server spire charts/spire \
--values tests/integration/psat/values.yaml \
--values examples/tornjak/values.yaml \
--values examples/tornjak/values-ingress.yaml \
--set global.spire.ingressControllerType=ingress-nginx \
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
helm upgrade --install -n spire-mgmt spire spire \
--repo https://spiffe.github.io/helm-charts-hardened/ \
--set global.openshift=true \
--set global.spire.trustDomain=$appdomain \
--set spire-server.ca_subject.common_name=$appdomain \
--set spire-server.ingress.host=spire-server.$appdomain \
--values examples/tornjak/values.yaml \
--values examples/tornjak/values-ingress.yaml \
--values your-values.yaml \
--render-subchart-notes
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

```shell
echo "https://tornjak-frontend.$appdomain"
```
