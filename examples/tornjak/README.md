# Recommended setup to deploy Tornjak

> [!WARNING]
> The default version of Tornjak in this chart is deployed without authentication. Therefore it is not suitable to run this version in production. In order to enable the user authentication,
> follow [Keycloak instructions](keycloak/README.md)

## Deploy Standard SPIRE

Follow the production installation of SPIRE as described in the [install instructions] (https://artifacthub.io/packages/helm/spiffe/spire) document.

## Upgrade to enable Tornjak

Before we can deploy Tornjak with SPIRE we need to decide whether the services would be
using direct access, Ingress, or some other method.

## Tornjak with Direct Access

This can be done using port-forward. For example, to start Tornjak APIs on port 10000

Deploy SPIRE with Tornjak enabled

```shell
export TORNJAK_API=http://localhost:10000

helm upgrade --install -n spire-mgmt spire spire \
--repo https://spiffe.github.io/helm-charts-hardened/ \
--set tornjak-frontend.apiServerURL=$TORNJAK_API \
--values examples/tornjak/values.yaml \
--values your-values.yaml \
--render-subchart-notes

# test the Tornjak deployment
helm test spire -n spire-server
```

Run following commands from your shell, to start port forwarding for Tornjak backend (APIs)
and Tornjak frontend (UI) services.
 If you deployed in different namespace, your values might differ. Consult the install notes printed when running above `helm upgrade` command in that case.

Since `port-forward` is a blocking command, execute them in two different consoles:

```shell
kubectl -n spire-server port-forward service/spire-tornjak-backend 10000:10000
```

```shell
kubectl -n spire-server port-forward service/spire-tornjak-frontend 3000:3000
```

You can now access Tornjak with your browser at [localhost:3000](http://localhost:3000).

See [values.yaml](./values.yaml) for more details on the chart configurations to achieve this setup.

## Deploy Tornjak with ingress-nginx

Update your-values.yaml with your ingress information, most importantly, trustDomain, and redeploy
adding the following:

```shell
--set global.spire.ingressControllerType=ingress-nginx \
--values examples/tornjak/values-ingress.yaml
```

## Deploy Tornjak with Ingress on Openshift

Obtain the OpenShift Apps Subdomain for Ingress and assign it to the `trustDomain`
environment variable:

```shell
export appdomain=$(oc get cm -n openshift-config-managed  console-public -o go-template="{{ .data.consoleURL }}" | sed 's@https://@@; s/^[^.]*\.//')
echo $appdomain
```

So it can be passed as follow:

```shell
--set global.openshift=true \
--set global.spire.trustDomain=$appdomain \
--values examples/tornjak/values-ingress.yaml \
```

When running on Openshift in some environments like IBM Cloud,
you might need to also add the following configurations:

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
