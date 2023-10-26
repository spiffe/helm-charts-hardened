# spire

![Version: 0.14.0](https://img.shields.io/badge/Version-0.13.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.7.2](https://img.shields.io/badge/AppVersion-1.7.2-informational?style=flat-square)
[![Development Phase](https://github.com/spiffe/spiffe/blob/main/.img/maturity/dev.svg)](https://github.com/spiffe/spiffe/blob/main/MATURITY.md#development)

A Helm chart for deploying the complete Spire stack including: spire-server, spire-agent, spiffe-csi-driver, spiffe-oidc-discovery-provider and spire-controller-manager.

**Homepage:** <https://github.com/spiffe/helm-charts/tree/main/charts/spire>

## Install notes

To do a quick non production install suitable for quick testing in something like minikube:

```shell
kubectl create namespace spire-system
helm install -n spire-system spire-crds --repo https://spiffe.github.io/helm-charts-hardened/
helm install -n spire-system spire --repo https://spiffe.github.io/helm-charts-hardened/
```

To customize, start with a base values file and edit as needed:

```shell
curl -o your-values.yaml https://raw.githubusercontent.com/spiffe/helm-charts-hardened/main/examples/production/example-your-values.yaml
```

Then:

```shell
helm install -n spire-system spire --repo https://spiffe.github.io/helm-charts-hardened/ -f your-values.yaml
```

For production installs, please see [the production example](https://github.com/spiffe/helm-charts-hardened/tree/main/examples/production).

## Upgrade notes

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

> **Note**: This Chart is still in development and still subject to change the API (`values.yaml`).
> Until we reach a `1.0.0` version of the chart we can't guarantee backwards compatibility although
> we do aim for as much stability as possible.

| Dependency | Supported Versions |
|:-----------|:-------------------|
| Helm       | `3.x`              |
| Kubernetes | `1.22+`            |

> **Note**: For Kubernetes, we will officially support the last 3 versions as described in [k8s versioning](https://kubernetes.io/releases/version-skew-policy/#supported-versions). Any version before the last 3 we will try to support as long it doesn't bring security issues or any big maintenance burden.

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

* <https://github.com/spiffe/helm-charts/tree/main/charts/spire>

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

| Name                                    | Description                                                                                                                                                                                                       | Value                        |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------- |
| `global.k8s.clusterDomain`              | Cluster domain name configured for Spire install                                                                                                                                                                  | `cluster.local`              |
| `global.spire.bundleConfigMap`          | A configmap containing the Spire bundle                                                                                                                                                                           | `""`                         |
| `global.spire.clusterName`              | The name of the k8s cluster for Spire install                                                                                                                                                                     | `example-cluster`            |
| `global.spire.jwtIssuer`                | The issuer for Spire JWT tokens                                                                                                                                                                                   | `oidc-discovery.example.org` |
| `global.spire.trustDomain`              | The trust domain for Spire install                                                                                                                                                                                | `example.org`                |
| `global.spire.upstreamServerAddress`    | Set what address to use for the upstream server when using nested spire                                                                                                                                           | `""`                         |
| `global.spire.image.registry`           | Override all Spire image registries at once                                                                                                                                                                       | `""`                         |
| `global.spire.strictMode`               | Check values, such as trustDomain, are overridden with a suitable value for production.                                                                                                                           | `false`                      |
| `global.spire.ingressControllerType`    | Specify what type of ingress controller you're using to add the necessary annotations accordingly. If blank, other is assumed. If other, no annotations will be added. Must be one of [ingress-nginx, other, ""]. | `""`                         |
| `global.installAndUpgradeHooks.enabled` | Enable Helm hooks to autofix common install/upgrade issues (should be disabled when using `helm template`)                                                                                                        | `true`                       |
| `global.deleteHooks.enabled`            | Enable Helm hooks to autofix common delete issues (should be disabled when using `helm template`)                                                                                                                 | `true`                       |

### Spire server parameters

| Name                                     | Description                                   | Value    |
| ---------------------------------------- | --------------------------------------------- | -------- |
| `spire-server.enabled`                   | Flag to enable Spire server                   | `true`   |
| `spire-server.nameOverride`              | Overrides the name of Spire server pods       | `server` |
| `spire-server.controllerManager.enabled` | Enable controller manager and provision CRD's | `true`   |

### Spire agent parameters

| Name                       | Description                            | Value   |
| -------------------------- | -------------------------------------- | ------- |
| `spire-agent.enabled`      | Flag to enable Spire agent             | `true`  |
| `spire-agent.nameOverride` | Overrides the name of Spire agent pods | `agent` |

### Upstream Spire agent and CSI driver configuration

| Name               | Description                                                | Value   |
| ------------------ | ---------------------------------------------------------- | ------- |
| `upstream.enabled` | Enable upstream agent and driver for use with nested spire | `false` |

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

### SPIFFE CSI Driver parameters

| Name                        | Description                                      | Value  |
| --------------------------- | ------------------------------------------------ | ------ |
| `spiffe-csi-driver.enabled` | Flag to enable spiffe-csi-driver for the cluster | `true` |

### Upstream SPIFFE CSI Driver parameters

| Name                                           | Description                                                 | Value                                                |
| ---------------------------------------------- | ----------------------------------------------------------- | ---------------------------------------------------- |
| `upstream-spiffe-csi-driver.pluginName`        | The plugin name for configuring upstream Spiffe CSI driver  | `upstream.csi.spiffe.io`                             |
| `upstream-spiffe-csi-driver.agentSocketPath`   | The socket path where Spiffe CSI driver mounts agent socket | `/run/spire/agent-sockets-upstream/spire-agent.sock` |
| `upstream-spiffe-csi-driver.healthChecks.port` | The port where Spiffe CSI driver health checks are exposed  | `9810`                                               |

### SPIFFE oidc discovery provider parameters

| Name                                     | Description                                                   | Value   |
| ---------------------------------------- | ------------------------------------------------------------- | ------- |
| `spiffe-oidc-discovery-provider.enabled` | Flag to enable spiffe-oidc-discovery-provider for the cluster | `false` |

### Tornjak frontend parameters

| Name                       | Description                                                    | Value   |
| -------------------------- | -------------------------------------------------------------- | ------- |
| `tornjak-frontend.enabled` | Enables deployment of Tornjak frontend/UI (Not for production) | `false` |
