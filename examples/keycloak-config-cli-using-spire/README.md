# keycloak-config-cli using spire

> [!WARNING]
> This example uses
> the [`SidecarContainers`](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/#enabling-sidecar-containers)
> feature. This is only enabled by default in Kubernetes 1.29+.

This example shows how to leverage SPIRE in establishing an mTLS connection
between [Keycloak](https://www.keycloak.org/) and [keycloak-config-cli](https://github.com/adorsys/keycloak-config-cli),
a tool to configure Keycloak.

## Setup

1. Create a local cluster for testing

```shell
kind create cluster --image kindest/node:v1.29.0
```

2. Install CRDs

```shell
helm upgrade --install -n spire-server spire-crds ../../charts/spire-crds --create-namespace
```

3. Install `spire-server`

```shell
helm upgrade --install -n spire-server spire ../../charts/spire --create-namespace -f spire-values.yaml
```

4. Install `keycloak` (this also configures Keycloak for client certificate authentication)

```shell
helm upgrade --install keycloak oci://registry-1.docker.io/bitnamicharts/keycloak -f keycloak-values.yaml
```

5. Install `keycloak-config-cli`

```shell
kubectl apply -f keycloak-config-cli.yaml
```

6. Verify the realm config at the bottom of [keycloak-config-cli.yaml](./keycloak-config-cli.yaml) has been created!
7. Cleanup

```shell
kind delete cluster
```

## Notes

### java-spiffe-helper as Keycloak initContainer

This example uses [java-spiffe-helper](https://github.com/spiffe/java-spiffe/tree/main/java-spiffe-helper) as an
initContainer for Keycloak. It fetches the certificates from the `spire-agent` and conveniently provides them to
Keycloak in `pkcs12` format.

> [!IMPORTANT]
> Keycloak does not rotate the certificates like SPIRE does. If you want to run the `keycloak-config-cli`
> job again, you need to make sure Keycloak is also restarted/provided with non-expired certificates.

### Common name as username

This example is configured to read the username from the common name (`CN`) from the client certificate. Keycloak has
some options there, this looked like the easiest one. SPIRE joins the values from `dnsNameTemplates` in the
common name section of the certificate, so make sure you can somehow extract the username from it.
