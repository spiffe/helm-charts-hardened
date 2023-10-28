# Recommended setup for installing Spire on Openshift

> **Note**: This functionality is under development. It works but has no automated testing and will have security tightened in the future.

This deployment works only with Openshift version 4.13 or higher. Get the Openshift platform here: [try.openshift.com](try.openshift.com)

To be consistent with the rest of the Spire helm-charts,
we deploy Spire across 2 namespaces.

```shell
kubectl create namespace "spire-system"
kubectl create namespace "spire-server"
kubectl label namespace "spire-system" pod-security.kubernetes.io/enforce=privileged
kubectl label namespace "spire-server" pod-security.kubernetes.io/enforce=privileged
```

Update the `example-your-values.yaml` file with your values.

Obtain you ingress subdomain:

```shell
echo "apps.$(kubectl get dns cluster -o jsonpath='{ .spec.baseDomain }')"
```

_Note: The location of the apps subdomain may be different in certain environments_

## Standard Deployment

Deploy the charts:

```shell
helm upgrade --install --namespace spire-server spire charts/spire \
--values examples/production/values.yaml \
--values examples/openshift/openshift-values.yaml \
--values examples/tornjak/values.yaml \
--values examples/production/example-your-values.yaml \
--render-subchart-notes --debug
```

## IBM Cloud Deployment

Openshift on IBM Cloud requires additional configuration:

```shell
helm upgrade --install --namespace spire-server spire charts/spire \
--values examples/production/values.yaml \
--values examples/openshift/openshift-values.yaml \
--values examples/tornjak/values.yaml \
--set spiffe-csi-driver.kubeletPath=/var/data/kubelet \
--set spiffe-csi-driver.restrictedScc.enabled=true \
--values examples/production/example-your-values.yaml \
--render-subchart-notes --debug
```
