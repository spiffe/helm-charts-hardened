# spire

![Version: 0.20.0](https://img.shields.io/badge/Version-0.20.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.9.4](https://img.shields.io/badge/AppVersion-1.9.4-informational?style=flat-square)
[![Development Phase](https://github.com/spiffe/spiffe/blob/main/.img/maturity/dev.svg)](https://github.com/spiffe/spiffe/blob/main/MATURITY.md#development)

A Helm chart for deploying the complete Spire stack including: spire-server, spire-agent, spiffe-csi-driver, spiffe-oidc-discovery-provider and spire-controller-manager.

**Homepage:** <https://github.com/spiffe/helm-charts-hardened/tree/main/charts/spire>

## Install Instructions

### Non Production
To do a quick install suitable for testing in something like minikube:

```shell
helm upgrade --install -n spire-server spire-crds spire-crds --repo https://spiffe.github.io/helm-charts-hardened/ --create-namespace
helm upgrade --install -n spire-server spire spire --repo https://spiffe.github.io/helm-charts-hardened/
```

### Production

Preparing a production deployment requires a few steps.

1. Save the following to your-values.yaml, ideally in your git repo.
```yaml
global:
  openshift: false # If running on openshift, set to true
  spire:
    recommendations:
      enabled: true
    namespaces:
      create: true
    ingressControllerType: "" # If not openshift, and want to expose services, set to a supported option [ingress-nginx]
    # Update these
    clusterName: example-cluster
    trustDomain: example.org
    caSubject:
      country: ARPA
      organization: Example
      commonName: example.org
```

2. If you need a non default storageClass, append the following to the global.spire section and update:
```
    persistence:
      storageClass: your-storage-class
```

3. If your Kubernetes cluster is OpenShift based, use the output of the following command to update the trustDomain setting:
```shell
oc get cm -n openshift-config-managed  console-public -o go-template="{{ .data.consoleURL }}" | sed 's@https://@@; s/^[^.]*\.//'
```

4. Find any additional values you might want to set based on the documentation below or using the [examples](https://github.com/spiffe/helm-charts-hardened/tree/main/examples)

In particular, consider using an external database.

5. Deploy

```shell
helm upgrade --install -n spire-mgmt spire-crds spire-crds --repo https://spiffe.github.io/helm-charts-hardened/ --create-namespace
helm upgrade --install -n spire-mgmt spire spire --repo https://spiffe.github.io/helm-charts-hardened/ -f your-values.yaml
```

## Clean up

```shell
helm -n spire-mgmt uninstall spire-crds
helm -n spire-mgmt uninstall spire
kubectl -n spire-server delete pvc -l app.kubernetes.io/instance=spire
kubectl delete crds clusterfederatedtrustdomains.spire.spiffe.io clusterspiffeids.spire.spiffe.io clusterstaticentries.spire.spiffe.io
```

## Upgrade notes

We only support upgrading one major version at a time. Version skipping isn't supported.

### 0.20.X

- The default service port for the spire-server was changed to be port 443 to allow easier switching between internal access and external access through an ingress controller. For most users, this will be a transparent
change.

- This release configures the entries managed by the spire-controller-manager to move into their own managed space within SPIRE. This should be transparent. In a future release, we will
disable cleanup by default of the old space. This release lays the groundwork for future support for manually created entries in the SPIRE database without the spire-controller-manager
destroying them. It is supported in this release by manually setting spire-server.controllerManager.entryIDPrefixCleanup=false after successfully upgrading to the chart without the
setting and waiting for a spire-controller-manager sync.

### 0.19.X

- The spire-agent daemonset gained a new label. For those disabling the upgrade hooks, you need to delete the spire-agent daemonset before issuing the helm upgrade.

### 0.18.X

- SPIRE no longer emits x509UniqueIdentifiers in x509-SVIDS by default. The old behavior can be reenabled with spire-server.credentialComposer.uniqueID.enabled=true. See https://github.com/spiffe/spire/pull/4862 for details.
- SPIRE agents will now automatically reattest when they can. The old behavior can be reenabled with spire-agent.disableReattestToRenew=true. See https://github.com/spiffe/spire/pull/4791 for details.

### 0.17.X

- If you set spire-server.replicaCount > 1, update it to 1 before upgrading and after upgrade you can set it back to its previous value.
- The SPIFFE OIDC Discovery Provider now has many new TLS options and defaults to using SPIRE to issue its certificate.
- The `spiffe-oidc-discovery-provider.insecureScheme.enabled` flag was removed. If you previously set that flag, remove the setting from your values.yaml and see if the new default of using a SPIRE issued certificate is suitable for your deployment. If it isn't, please consider one of the other options under `spiffe-oidc-discovery-provider.tls`. If all other options are still unsuitable, you can still enable the previous mode by disabling TLS. (`spiffe-oidc-discovery-provider.tls.spire.enabled=false`)

- The SPIFFE OIDC Discovery Provider is now enabled by default. If you previously chose to have it off, you can disable it explicitly with `spiffe-oidc-discovery-provider.enabled=false`.

### 0.16.X

The settings under "spire-server.controllerManager.identities" have all been moved under "spire-server.controllerManager.identities.clusterSPIFFEIDs.default". If you have changed any from the defaults, please update them to the new location during upgrade.

### 0.15.X

The spire-crds chart has been updated. Please ensure you have upgraded spire-crds before upgrading the spire chart.

The chart now supports multiple parallel installs of spire-controller-manager. Each install will handle all custom resources with a matching `className` field.  By default this is set to `Release.Namespace-Release.Name` and the controller manager will only pick up custom resources with this `className`.

If you have not loaded any SPIRE custom resources yourself, the upgrade process will be transparent. If you have loaded your own SPIRE custom resources, set `spire-server.controllerManager.watchClassless=true` until you can update your SPIRE custom resources to have the `className` for the instance specified.

### 0.14.X

If coming from a chart version before 0.14.0, you must relabel your crds to switch to using the new spire-crds chart. To migrate to the spire-crds chart
run the following:

Replace the spire-server namespace in the commands below with the namespace you want to install the spire-crds chart in.

```shell
kubectl label crd "clusterfederatedtrustdomains.spire.spiffe.io" "app.kubernetes.io/managed-by=Helm"
kubectl annotate crd "clusterfederatedtrustdomains.spire.spiffe.io" "meta.helm.sh/release-name=spire-crds"
kubectl annotate crd "clusterfederatedtrustdomains.spire.spiffe.io" "meta.helm.sh/release-namespace=spire-server"
kubectl label crd "clusterspiffeids.spire.spiffe.io" "app.kubernetes.io/managed-by=Helm"
kubectl annotate crd "clusterspiffeids.spire.spiffe.io" "meta.helm.sh/release-name=spire-crds"
kubectl annotate crd "clusterspiffeids.spire.spiffe.io" "meta.helm.sh/release-namespace=spire-server"
kubectl label crd "controllermanagerconfigs.spire.spiffe.io" "app.kubernetes.io/managed-by=Helm"
kubectl annotate crd "controllermanagerconfigs.spire.spiffe.io" "meta.helm.sh/release-name=spire-crds"
kubectl annotate crd "controllermanagerconfigs.spire.spiffe.io" "meta.helm.sh/release-namespace=spire-server"
helm install -n spire-server spire-crds charts/spire-crds
```

## Version support

> [!Warning]
> This Chart is still in development and still subject to change the API (`values.yaml`).
> Until we reach a `1.0.0` version of the chart we can't guarantee backwards compatibility although
> we do aim for as much stability as possible.

| Dependency | Supported Versions |
|:-----------|:-------------------|
| Helm       | `3.x`              |
| Kubernetes | `1.22+`            |

> [!Note]
> For Kubernetes, we will officially support the last 3 versions as described in [k8s versioning](https://kubernetes.io/releases/version-skew-policy/#supported-versions). Any version before the last 3 we will try to support as long it doesn't bring security issues or any big maintenance burden.

## FAQ

For any issues see our [FAQ](../../FAQ.md)…

## Usage

To utilize Spire in your own workloads you should add the following to your workload:

```diff
 apiVersion: v1
 kind: Pod
 metadata:
   name: my-app
 spec:
   containers:
     - name: my-app
       image: "my-app:latest"
       imagePullPolicy: Always
+      volumeMounts:
+        - name: spiffe-workload-api
+          mountPath: /spiffe-workload-api
+          readOnly: true
       resources:
         requests:
           cpu: 200m
           memory: 32Mi
         limits:
           cpu: 500m
           memory: 64Mi
+  volumes:
+    - name: spiffe-workload-api
+      csi:
+        driver: "csi.spiffe.io"
+        readOnly: true
```

Now you can interact with the Spire agent socket from your own application. The socket is mounted on `/spiffe-workload-api/spire-agent.sock`.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| marcofranssen | <marco.franssen@gmail.com> | <https://marcofranssen.nl> |
| kfox1111 | <Kevin.Fox@pnnl.gov> |  |
| faisal-memon | <fymemon@yahoo.com> |  |
| edwbuck | <edwbuck@gmail.com> |  |

## Source Code

* <https://github.com/spiffe/helm-charts-hardened/tree/main/charts/spire>

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| file://./charts/spiffe-csi-driver | spiffe-csi-driver | 0.1.0 |
| file://./charts/spiffe-csi-driver | upstream-spiffe-csi-driver(spiffe-csi-driver) | 0.1.0 |
| file://./charts/spiffe-oidc-discovery-provider | spiffe-oidc-discovery-provider | 0.1.0 |
| file://./charts/spire-agent | spire-agent | 0.1.0 |
| file://./charts/spire-agent | upstream-spire-agent(spire-agent) | 0.1.0 |
| file://./charts/spire-server | spire-server | 0.1.0 |
| file://./charts/tornjak-frontend | tornjak-frontend | 0.1.0 |

<!-- The parameters section is generated using helm-docs.sh and should not be edited by hand. -->

## Parameters

### Global parameters

| Name                                             | Description                                                                                                                                                                                                                            | Value             |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| `global.k8s.clusterDomain`                       | Cluster domain name configured for Spire install                                                                                                                                                                                       | `cluster.local`   |
| `global.spire.bundleConfigMap`                   | A configmap containing the Spire bundle                                                                                                                                                                                                | `""`              |
| `global.spire.clusterName`                       | The name of the k8s cluster for Spire install                                                                                                                                                                                          | `example-cluster` |
| `global.spire.jwtIssuer`                         | The issuer for Spire JWT tokens. Defaults to oidc-discovery.$trustDomain if unset                                                                                                                                                      | `""`              |
| `global.spire.trustDomain`                       | The trust domain for Spire install                                                                                                                                                                                                     | `example.org`     |
| `global.spire.upstreamServerAddress`             | Set what address to use for the upstream server when using nested spire                                                                                                                                                                | `""`              |
| `global.spire.caSubject.country`                 | Country for Spire server CA                                                                                                                                                                                                            | `""`              |
| `global.spire.caSubject.organization`            | Organization for Spire server CA                                                                                                                                                                                                       | `""`              |
| `global.spire.caSubject.commonName`              | Common Name for Spire server CA                                                                                                                                                                                                        | `""`              |
| `global.spire.persistence.storageClass`          | What storage class to use for persistence                                                                                                                                                                                              | `nil`             |
| `global.spire.recommendations.enabled`           | Use recommended settings for production deployments. Default is off.                                                                                                                                                                   | `false`           |
| `global.spire.recommendations.namespaceLayout`   | Set to true to use recommended values for installing across namespaces                                                                                                                                                                 | `true`            |
| `global.spire.recommendations.namespacePSS`      | When chart namespace creation is enabled, label them with preffered Pod Security Standard labels                                                                                                                                       | `true`            |
| `global.spire.recommendations.priorityClassName` | Set to true to use recommended values for Pod Priority Class Names                                                                                                                                                                     | `true`            |
| `global.spire.recommendations.strictMode`        | Check values, such as trustDomain, are overridden with a suitable value for production.                                                                                                                                                | `true`            |
| `global.spire.recommendations.securityContexts`  | Set to true to use recommended values for Pod and Container Security Contexts                                                                                                                                                          | `true`            |
| `global.spire.recommendations.prometheus`        | Enable prometheus exporters for monitoring                                                                                                                                                                                             | `true`            |
| `global.spire.image.registry`                    | Override all Spire image registries at once                                                                                                                                                                                            | `""`              |
| `global.spire.namespaces.create`                 | Set to true to Create all namespaces. If this or either of the namespace specific create flags is set, the namespace will be created.                                                                                                  | `false`           |
| `global.spire.namespaces.system.name`            | Name of the Spire system Namespace.                                                                                                                                                                                                    | `spire-system`    |
| `global.spire.namespaces.system.create`          | Create a Namespace for Spire system resources.                                                                                                                                                                                         | `false`           |
| `global.spire.namespaces.system.annotations`     | Annotations to apply to the Spire system Namespace.                                                                                                                                                                                    | `{}`              |
| `global.spire.namespaces.system.labels`          | Labels to apply to the Spire system Namespace.                                                                                                                                                                                         | `{}`              |
| `global.spire.namespaces.server.name`            | Name of the Spire server Namespace.                                                                                                                                                                                                    | `spire-server`    |
| `global.spire.namespaces.server.create`          | Create a Namespace for Spire server resources.                                                                                                                                                                                         | `false`           |
| `global.spire.namespaces.server.annotations`     | Annotations to apply to the Spire server Namespace.                                                                                                                                                                                    | `{}`              |
| `global.spire.namespaces.server.labels`          | Labels to apply to the Spire server Namespace.                                                                                                                                                                                         | `{}`              |
| `global.spire.strictMode`                        | Check values, such as trustDomain, are overridden with a suitable value for production.                                                                                                                                                | `false`           |
| `global.spire.ingressControllerType`             | Specify what type of ingress controller you're using to add the necessary annotations accordingly. If blank, autodetection is attempted. If other, no annotations will be added. Must be one of [ingress-nginx, openshift, other, ""]. | `""`              |
| `global.spire.tools.kubectl.tag`                 | Set to force the tag to use for all kubectl instances                                                                                                                                                                                  | `""`              |
| `global.installAndUpgradeHooks.enabled`          | Enable Helm hooks to autofix common install/upgrade issues (should be disabled when using `helm template`)                                                                                                                             | `true`            |
| `global.deleteHooks.enabled`                     | Enable Helm hooks to autofix common delete issues (should be disabled when using `helm template`)                                                                                                                                      | `true`            |

### Spire server parameters

| Name                                              | Description                                                               | Value         |
| ------------------------------------------------- | ------------------------------------------------------------------------- | ------------- |
| `spire-server.nameOverride`                       | Overrides the name of Spire server pods                                   | `server`      |
| `spire-server.kind`                               | Run spire server as deployment/statefulset. This feature is experimental. | `statefulset` |
| `spire-server.controllerManager.enabled`          | Enable controller manager and provision CRD's                             | `true`        |
| `spire-server.externalControllerManagers.enabled` | Enable external controller manager support                                | `true`        |

### Spire agent parameters

| Name                       | Description                            | Value   |
| -------------------------- | -------------------------------------- | ------- |
| `spire-agent.nameOverride` | Overrides the name of Spire agent pods | `agent` |

### Tornjak frontend parameters

| Name                       | Description                                                    | Value   |
| -------------------------- | -------------------------------------------------------------- | ------- |
| `tornjak-frontend.enabled` | Enables deployment of Tornjak frontend/UI (Not for production) | `false` |

### Spire agent parameters

| Name                                              | Description                                                   | Value                     |
| ------------------------------------------------- | ------------------------------------------------------------- | ------------------------- |
| `downstream-spire-agent-full.nameOverride`        | Overrides the name of Spire agent pods                        | `agent-downstream`        |
| `downstream-spire-agent-full.server.nameOverride` | The name override setting of the internal SPIRE server        | `internal-server`         |
| `downstream-spire-agent-full.bundleConfigMap`     | The name of the configmap that contains the downstream bundle | `spire-bundle-downstream` |

### Spire agent parameters

| Name                                                  | Description                                                   | Value                   |
| ----------------------------------------------------- | ------------------------------------------------------------- | ----------------------- |
| `downstream-spire-agent-security.nameOverride`        | Overrides the name of Spire agent pods                        | `agent-downstream`      |
| `downstream-spire-agent-security.bundleConfigMap`     | The name of the configmap that contains the downstream bundle | `spire-bundle-upstream` |
| `downstream-spire-agent-security.serviceAccount.name` | The name of the service account to use                        | `spire-agent-upstream`  |

### Upstream Spire agent parameters

| Name                                             | Description                                        | Value                                                |
| ------------------------------------------------ | -------------------------------------------------- | ---------------------------------------------------- |
| `upstream-spire-agent.upstream`                  | Flag for enabling upstream Spire agent             | `true`                                               |
| `upstream-spire-agent.nameOverride`              | Name override for upstream Spire agent             | `agent-upstream`                                     |
| `upstream-spire-agent.bundleConfigMap`           | The configmap name for upstream Spire agent bundle | `spire-bundle-upstream`                              |
| `upstream-spire-agent.socketPath`                | Socket path where Spire agent socket is mounted    | `/run/spire/agent-sockets-upstream/spire-agent.sock` |
| `upstream-spire-agent.serviceAccount.name`       | Service account name for upstream Spire agent      | `spire-agent-upstream`                               |
| `upstream-spire-agent.healthChecks.port`         | Health check port number for upstream Spire agent  | `9981`                                               |
| `upstream-spire-agent.telemetry.prometheus.port` | The port where prometheus metrics are available    | `9989`                                               |
| `upstream-spire-agent.server.nameOverride`       | The name override setting of the root SPIRE server | `root-server`                                        |

### SPIFFE CSI Driver parameters

| Name                                            | Description       | Value                          |
| ----------------------------------------------- | ----------------- | ------------------------------ |
| `downstream-spiffe-csi-driver.fullnameOverride` | Fullname override | `spiffe-csi-driver-downstream` |

### Upstream SPIFFE CSI Driver parameters

| Name                                                                                                            | Description                                                                                                                                       | Value                                                |
| --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `upstream-spiffe-csi-driver.fullnameOverride`                                                                   | Fullname override                                                                                                                                 | `spiffe-csi-driver-upstream`                         |
| `upstream-spiffe-csi-driver.pluginName`                                                                         | The plugin name for configuring upstream Spiffe CSI driver                                                                                        | `upstream.csi.spiffe.io`                             |
| `upstream-spiffe-csi-driver.agentSocketPath`                                                                    | The socket path where Spiffe CSI driver mounts agent socket                                                                                       | `/run/spire/agent-sockets-upstream/spire-agent.sock` |
| `upstream-spiffe-csi-driver.healthChecks.port`                                                                  | The port where Spiffe CSI driver health checks are exposed                                                                                        | `9810`                                               |
| `root-spire-server.nameOverride`                                                                                | Name override                                                                                                                                     | `root-server`                                        |
| `root-spire-server.crNameOverride`                                                                              | Custom Resource name override                                                                                                                     | `root`                                               |
| `root-spire-server.controllerManager.enabled`                                                                   | Enable controller manager and provision CRD's                                                                                                     | `true`                                               |
| `root-spire-server.controllerManager.externalControllerManagers.enabled`                                        | Flag to enable external controller managers                                                                                                       | `true`                                               |
| `root-spire-server.controllerManager.validatingWebhookConfiguration.enabled`                                    | Disable only when you have another instance on the k8s cluster with webhooks enabled.                                                             | `false`                                              |
| `root-spire-server.controllerManager.className`                                                                 | specify to use an explicit class name.                                                                                                            | `spire-mgmt-root-server`                             |
| `root-spire-server.controllerManager.identities.clusterSPIFFEIDs.child-servers.enabled`                         | Enable child servers                                                                                                                              | `true`                                               |
| `root-spire-server.controllerManager.identities.clusterSPIFFEIDs.default.enabled`                               | Enable the default cluster spiffe id                                                                                                              | `false`                                              |
| `root-spire-server.controllerManager.identities.clusterSPIFFEIDs.oidc-discovery-provider.enabled`               | Enable the test-keys identity                                                                                                                     | `false`                                              |
| `root-spire-server.controllerManager.identities.clusterSPIFFEIDs.test-keys.enabled`                             | Enable the test-keys identity                                                                                                                     | `false`                                              |
| `root-spire-server.externalControllerManagers.enabled`                                                          | Flag to enable external controller managers                                                                                                       | `true`                                               |
| `root-spire-server.nodeAttestor.k8sPsat.serviceAccountAllowList`                                                | Allowed service accounts for Psat nodeattestor                                                                                                    | `[]`                                                 |
| `root-spire-server.bundleConfigMap`                                                                             | The name of the configmap to store the upstream bundle                                                                                            | `spire-bundle-upstream`                              |
| `external-root-spire-server-full.externalServer`                                                                | Set to true to setup the bundle configmap, rbac rules, and identity documents but doesn't deploy the server locally. Useful for external servers. | `true`                                               |
| `external-root-spire-server-full.nameOverride`                                                                  | Name override                                                                                                                                     | `root-server`                                        |
| `external-root-spire-server-full.crNameOverride`                                                                | Custom Resource name override                                                                                                                     | `root`                                               |
| `external-root-spire-server-full.controllerManager.enabled`                                                     | Enable controller manager and provision CRD's                                                                                                     | `true`                                               |
| `external-root-spire-server-full.controllerManager.validatingWebhookConfiguration.enabled`                      | Disable only when you have another instance on the k8s cluster with webhooks enabled.                                                             | `false`                                              |
| `external-root-spire-server-full.controllerManager.className`                                                   | specify to use an explicit class name.                                                                                                            | `spire-mgmt-external-server`                         |
| `external-root-spire-server-full.controllerManager.identities.clusterSPIFFEIDs.child-servers.enabled`           | Enable child servers                                                                                                                              | `true`                                               |
| `external-root-spire-server-full.controllerManager.identities.clusterSPIFFEIDs.default.enabled`                 | Enable the default cluster spiffe id                                                                                                              | `false`                                              |
| `external-root-spire-server-full.controllerManager.identities.clusterSPIFFEIDs.oidc-discovery-provider.enabled` | Enable the test-keys identity                                                                                                                     | `false`                                              |
| `external-root-spire-server-full.controllerManager.identities.clusterSPIFFEIDs.test-keys.enabled`               | Enable the test-keys identity                                                                                                                     | `false`                                              |
| `external-root-spire-server-full.nodeAttestor.k8sPsat.serviceAccountAllowList`                                  | Allowed service accounts for Psat nodeattestor                                                                                                    | `[]`                                                 |
| `external-root-spire-server-full.bundleConfigMap`                                                               | The name of the configmap to store the upstream bundle                                                                                            | `spire-bundle-upstream`                              |
| `external-root-spire-server-security.externalServer`                                                            | Set to true to setup the bundle configmap, rbac rules, and identity documents but doesn't deploy the server locally. Useful for external servers. | `true`                                               |
| `external-root-spire-server-security.nameOverride`                                                              | Name override                                                                                                                                     | `root-server`                                        |
| `external-root-spire-server-security.crNameOverride`                                                            | Custom Resource name override                                                                                                                     | `root`                                               |
| `external-root-spire-server-security.controllerManager.enabled`                                                 | Enable controller manager and provision CRD's                                                                                                     | `true`                                               |
| `external-root-spire-server-security.controllerManager.validatingWebhookConfiguration.enabled`                  | Disable only when you have another instance on the k8s cluster with webhooks enabled.                                                             | `false`                                              |
| `external-root-spire-server-security.controllerManager.className`                                               | specify to use an explicit class name.                                                                                                            | `spire-mgmt-external-server`                         |
| `external-root-spire-server-security.nodeAttestor.k8sPsat.serviceAccountAllowList`                              | Allowed service accounts for Psat nodeattestor                                                                                                    | `[]`                                                 |
| `external-root-spire-server-security.bundleConfigMap`                                                           | The name of the configmap to store the upstream bundle                                                                                            | `spire-bundle-upstream`                              |

### Spire server parameters

| Name                                                                                                               | Description                                                                           | Value                        |
| ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------- | ---------------------------- |
| `internal-spire-server.nameOverride`                                                                               | Overrides the name of Spire server pods                                               | `internal-server`            |
| `internal-spire-server.controllerManager.enabled`                                                                  | Enable controller manager and provision CRD's                                         | `true`                       |
| `internal-spire-server.controllerManager.identities.clusterSPIFFEIDs.oidc-discovery-provider.autoPopulateDNSNames` | Auto populate dns entries                                                             | `false`                      |
| `internal-spire-server.externalControllerManagers.enabled`                                                         | Flag to enable external controller managers                                           | `true`                       |
| `internal-spire-server.upstreamAuthority.spire.enabled`                                                            | Enable upstream SPIRE server                                                          | `true`                       |
| `internal-spire-server.upstreamAuthority.spire.upstreamDriver`                                                     | Use an upstream driver for authentication                                             | `upstream.csi.spiffe.io`     |
| `internal-spire-server.upstreamAuthority.spire.server.nameOverride`                                                | The name override setting of the root SPIRE server                                    | `root-server`                |
| `internal-spire-server.bundleConfigMap`                                                                            | The name of the configmap to store the downstream bundle                              | `spire-bundle-downstream`    |
| `external-spire-server.nameOverride`                                                                               | Overrides the name of Spire server pods                                               | `external-server`            |
| `external-spire-server.crNameOverride`                                                                             | Custom Resource name override                                                         | `external`                   |
| `external-spire-server.controllerManager.enabled`                                                                  | Enable controller manager and provision CRD's                                         | `true`                       |
| `external-spire-server.controllerManager.validatingWebhookConfiguration.enabled`                                   | Disable only when you have another instance on the k8s cluster with webhooks enabled. | `false`                      |
| `external-spire-server.controllerManager.className`                                                                | specify to use an explicit class name.                                                | `spire-mgmt-external-server` |
| `external-spire-server.controllerManager.identities.clusterSPIFFEIDs.default.enabled`                              | Enable the default identity                                                           | `false`                      |
| `external-spire-server.controllerManager.identities.clusterSPIFFEIDs.oidc-discovery-provider.enabled`              | Enable the oidc-discovery-provider identity                                           | `false`                      |
| `external-spire-server.controllerManager.identities.clusterSPIFFEIDs.test-keys.enabled`                            | Enable the test-keys identity                                                         | `false`                      |
| `external-spire-server.externalControllerManagers.enabled`                                                         | Flag to enable external controller managers                                           | `true`                       |
| `external-spire-server.upstreamAuthority.spire.enabled`                                                            | Enable upstream SPIRE server                                                          | `true`                       |
| `external-spire-server.upstreamAuthority.spire.upstreamDriver`                                                     | Use an upstream driver for authentication                                             | `upstream.csi.spiffe.io`     |
| `external-spire-server.upstreamAuthority.spire.server.nameOverride`                                                | The name override setting of the root SPIRE server                                    | `root-server`                |
| `external-spire-server.notifier.k8sbundle.enabled`                                                                 | Enable local k8s bundle uploader                                                      | `false`                      |
| `external-spire-server.nodeAttestor.k8sPsat.enabled`                                                               | Enable Psat k8s nodeattestor                                                          | `false`                      |
| `external-spire-server.nodeAttestor.joinToken.enabled`                                                             | Enable the join_token nodeattestor                                                    | `true`                       |
