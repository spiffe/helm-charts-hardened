# Recommended setup for installing Spire on Openshift

> [!Note]
> This functionality is under development. It works but has no automated testing and will have security tightened in the future.

This deployment works only with Openshift version 4.13 or higher. Get the Openshift platform here: [try.openshift.com](try.openshift.com)

To be consistent with the rest of the Spire helm-charts,
we deploy Spire across 2 namespaces, then install CRDs. 

> [!Note]
> Openshift install requires privilege due to helm ordering issue. This work is already done in [openshift-values.yaml](./openshift-values.yaml). After install it can be safely tightened back up.

```shell
kubectl create namespace "spire-system"
kubectl create namespace "spire-server"

helm upgrade --install --namespace spire-server spire-crds charts/spire-crds
```

Obtain you ingress subdomain:

```shell
appdomain=$(oc get cm -n openshift-config-managed  console-public -o go-template="{{ .data.consoleURL }}" | sed 's@https://@@; s/^[^.]*\.//')
echo "$appdomain"
```

Update the `example-your-values.yaml` file with your subdomain.

> [!Note]
> The location of the apps subdomain may be different in certain environments_

## Standard Deployment

```shell
helm upgrade --install --namespace spire-server spire charts/spire \
--values examples/production/values.yaml \
--values examples/openshift/openshift-values.yaml \
--values examples/production/example-your-values.yaml \
--render-subchart-notes
```

## IBM Cloud Deployment

Openshift on IBM Cloud requires additional configuration:

```shell
helm upgrade --install --namespace spire-server spire charts/spire \
--values examples/production/values.yaml \
--values examples/openshift/openshift-values.yaml \
--set spiffe-csi-driver.kubeletPath=/var/data/kubelet \
--set spiffe-csi-driver.restrictedScc.enabled=true \
--values examples/production/example-your-values.yaml \
--render-subchart-notes
```

## Feature Customization

Additional features such as tornjak can be enabled by including their example values files before --values examples/production/example-your-values.yaml

For example:

```shell
--values examples/openshift/openshift-values.yaml \
--values examples/tornjak/values.yaml \
--values examples/production/example-your-values.yaml \
```

## Finish install

Once installed, the namespace security can be tightened back up.

```shell
kubectl label namespace "spire-server" pod-security.kubernetes.io/enforce=restricted --overwrite
```
