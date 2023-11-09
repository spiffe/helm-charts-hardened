# Recommended setup to deploy Tornjak

> [!Warning]
> The current version of Tornjak in this chart is deployed without authentication. Therefore it is not suitable to run this version in production.

To install Spire with the least privileges possible we deploy spire across 2 namespaces.

```shell
kubectl create namespace "spire-system"
kubectl label namespace "spire-system" pod-security.kubernetes.io/enforce=privileged
kubectl create namespace "spire-server"
kubectl label namespace "spire-server" pod-security.kubernetes.io/enforce=restricted

# deploy SPIRE with Tornjak enabled
helm upgrade --install --namespace spire-server \
  --values ../production/values.yaml \
  --values ./values.yaml \
  --render-subchart-notes \
  spire ../../charts/spire

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

## Tornjak and Ingress

Obtain the Ingress subdomain (this process is cloud provider specific) and assign it
to the `APP_SUBDOMAIN` env. variable, then run the deployment with your values files:

```shell
export APP_SUBDOMAIN=$(kubectl get dns cluster -o jsonpath='{ .spec.baseDomain }')
echo $APP_SUBDOMAIN
```

Update the `values-ingress.yaml` file with your subdomain.

_Note: The location of the apps subdomain may be different in certain environments_

Then run the deployment with your values files:

```shell
helm upgrade --install --namespace spire-server spire charts/spire \
--values examples/production/values.yaml \
--values examples/tornjak/values.yaml \
--values examples/production/example-your-values.yaml \
--values examples/tornjak/values-ingress.yaml \
--render-subchart-notes --debug
```

## Tornjak and Ingress on Openshift

When deploying on Openshift, follow the deployment setup as described in
[Openshift README](../openshift/README.md)

Then just add Openshift specific configuration to the above command:
```shell
--values examples/openshift/openshift-values.yaml
```

When running on Openshift in some environments like IBM Cloud,
you might need to add the following configurations:

```shell
--set spiffe-csi-driver.kubeletPath=/var/data/kubelet \
--set spiffe-csi-driver.restrictedScc.enabled=true \
```
