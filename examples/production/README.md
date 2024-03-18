# Recommended production setup

## CRD Deployment

Current deployment charts allow creating namespaces as a part of the helm chart deployment.
In this case we can create a temporary namespace `spire-mgmt` that is only used during the deployment:

```shell
helm upgrade --install --create-namespace -n spire-mgmt spire-crds charts/spire-crds
```

## SPIRE Deployment

Update the `example-your-values.yaml` file with your values, then deploy:

```shell
helm upgrade --install --namespace spire-mgmt spire charts/spire --set global.spire.namespaces.create=true -f examples/production/values.yaml -f examples/production/example-your-values.yaml --render-subchart-notes
```

If your using ingress-nginx and want to expose the spiffe oidc discovery provider outside the
cluster, add the following to the end of the helm upgrade example:

```shell
-f examples/production/values-expose-spiffe-oidc-discovery-provider-ingress-nginx.yaml
```

If you want to expose your spire-server outside of Kubernetes and are using ingress-nginx, add following values file when running `helm template/install/upgrade`.

```shell
-f examples/production/values-expose-spire-server-ingress-nginx.yaml
```

For example:

```shell
helm upgrade --install --namespace spire-mgmt spire charts/spire --set global.spire.namespaces.create=true -f examples/production/values.yaml -f examples/production/values-expose-spire-server-ingress-nginx.yaml
```

If you want to expose your federation endpoint outside of Kubernetes and are using ingress-nginx
you have two options as described here:
[github.com/spiffe/spiffe/blob/main/standards/SPIFFE_Federation.md#52-endpoint-profiles](https://github.com/spiffe/spiffe/blob/main/standards/SPIFFE_Federation.md#52-endpoint-profiles)

If you chose profile https_web, use:

```shell
-f examples/production/values-expose-federation-https-web-ingress-nginx.yaml
```

For example:

```shell
helm upgrade --install --namespace spire-mgmt spire charts/spire --set global.spire.namespaces.create=true -f examples/production/values.yaml -f examples/production/values-expose-federation-https-web-ingress-nginx.yaml
```

If you chose profile https_spiffe, use:

```shell
-f examples/production/values-expose-federation-https-spiffe-ingress-nginx.yaml
```

For example:

```shell
helm upgrade --install --namespace spire-mgmt spire charts/spire --set global.spire.namespaces.create=true -f examples/production/values.yaml -f examples/production/values-expose-federation-https-spiffe-ingress-nginx.yaml
```

See [values.yaml](./values.yaml) for more details on the chart configurations to achieve this setup.
