# Recommended setup for installing Spire on Openshift

This deployment works only with Openshift version 4.13 or higher. Get the Openshift platform here: [try.openshift.com](try.openshift.com)

To be consistent with the rest of the Spire helm-charts,
we deploy Spire across 2 namespaces.

```shell
kubectl create namespace "spire-system"
kubectl create namespace "spire-server"
kubectl label namespace "spire-system" pod-security.kubernetes.io/enforce=privileged
kubectl label namespace "spire-server" pod-security.kubernetes.io/enforce=privileged
```

Update the `example-your-values.yaml` file with your values

## Standard Deployment

```shell
APP_SUBDOMAIN=apps.$(kubectl get dns cluster -o jsonpath='{ .spec.baseDomain }') envsubst < examples/openshift/openshift-values.yaml | helm upgrade --install --namespace spire-server spire charts/spire --values examples/production/values.yaml --values examples/tornjak/values.yaml --values - --render-subchart-notes --debug
```

## IBM Cloud Deployment

```shell
APP_SUBDOMAIN=$(kubectl get dns cluster -o jsonpath='{ .spec.baseDomain }') envsubst < examples/openshift/openshift-values.yaml | helm upgrade --install --namespace spire-server spire charts/spire --values examples/production/values.yaml --values examples/tornjak/values.yaml --values examples/production/example-your-values.yaml --values - --set spiffe-csi-driver.kubeletPath=/var/data/kubelet --set spiffe-csi-driver.restrictedScc.enabled=true  --render-subchart-notes --debug
```

_Note: The location of the apps subdomain may be different in certain environments_
