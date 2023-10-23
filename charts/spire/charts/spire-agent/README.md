# spire-agent

<!-- This README.md is generated. Please edit README.md.gotmpl -->

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.7.2](https://img.shields.io/badge/AppVersion-1.7.2-informational?style=flat-square)

A Helm chart to install the SPIRE agent.

**Homepage:** <https://github.com/spiffe/helm-charts/tree/main/charts/spire>

> **Note**: Minimum Spire version is `1.5.3`.
> The recommended version is `1.6.0` to support arm64 nodes. If running with any
> prior version to `1.6.0` you have to use a `nodeSelector` to limit to `kubernetes.io/arch: amd64`.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| marcofranssen | <marco.franssen@gmail.com> | <https://marcofranssen.nl> |
| kfox1111 | <Kevin.Fox@pnnl.gov> |  |
| faisal-memon | <fymemon@yahoo.com> |  |
| edwbuck | <edwbuck@gmail.com> |  |

## Source Code

* <https://github.com/spiffe/helm-charts/tree/main/charts/spire>

## Parameters

### Chart parameters

| Name                                              | Description                                                                                                         | Value                                                                            |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `image.registry`                                  | The OCI registry to pull the image from                                                                             | `ghcr.io`                                                                        |
| `image.repository`                                | The repository within the registry                                                                                  | `spiffe/spire-agent`                                                             |
| `image.pullPolicy`                                | The image pull policy                                                                                               | `IfNotPresent`                                                                   |
| `image.version`                                   | This value is deprecated in favor of tag. (Will be removed in a future release)                                     | `""`                                                                             |
| `image.tag`                                       | Overrides the image tag whose default is the chart appVersion                                                       | `""`                                                                             |
| `imagePullSecrets`                                | Pull secrets for images                                                                                             | `[]`                                                                             |
| `nameOverride`                                    | Name override                                                                                                       | `""`                                                                             |
| `namespaceOverride`                               | Namespace override                                                                                                  | `""`                                                                             |
| `fullnameOverride`                                | Fullname override                                                                                                   | `""`                                                                             |
| `serviceAccount.create`                           | Specifies whether a service account should be created                                                               | `true`                                                                           |
| `serviceAccount.annotations`                      | Annotations to add to the service account                                                                           | `{}`                                                                             |
| `serviceAccount.name`                             | The name of the service account to use.                                                                             | `""`                                                                             |
| `configMap.annotations`                           | Annotations to add to the SPIRE Agent ConfigMap                                                                     | `{}`                                                                             |
| `podAnnotations`                                  | Annotations to add to pods                                                                                          | `{}`                                                                             |
| `podSecurityContext`                              | Pod security context                                                                                                | `{}`                                                                             |
| `securityContext`                                 | Security context                                                                                                    | `{}`                                                                             |
| `resources`                                       | Resource requests and limits                                                                                        | `{}`                                                                             |
| `nodeSelector`                                    | Node selector                                                                                                       | `{}`                                                                             |
| `tolerations`                                     | List of tolerations                                                                                                 | `[]`                                                                             |
| `logLevel`                                        | The log level, valid values are "debug", "info", "warn", and "error"                                                | `info`                                                                           |
| `clusterName`                                     | The name of the Kubernetes cluster (`kubeadm init --service-dns-domain`)                                            | `example-cluster`                                                                |
| `trustDomain`                                     | The trust domain to be used for the SPIFFE identifiers                                                              | `example.org`                                                                    |
| `trustBundleURL`                                  | If set, obtain trust bundle from url instead of Kubernetes ConfigMap                                                | `""`                                                                             |
| `trustBundleFormat`                               | If using trustBundleURL, what format is the url. Choices are "pem" and "spiffe"                                     | `pem`                                                                            |
| `bundleConfigMap`                                 | Configmap name for Spire bundle                                                                                     | `spire-bundle`                                                                   |
| `server.address`                                  | Address for Spire server                                                                                            | `""`                                                                             |
| `server.port`                                     | Port number for Spire server                                                                                        | `8081`                                                                           |
| `server.namespaceOverride`                        | Override the namespace for Spire server                                                                             | `""`                                                                             |
| `healthChecks.port`                               | override the host port used for health checking                                                                     | `9980`                                                                           |
| `livenessProbe.initialDelaySeconds`               | Initial delay seconds for probe                                                                                     | `15`                                                                             |
| `livenessProbe.periodSeconds`                     | Period seconds for probe                                                                                            | `60`                                                                             |
| `readinessProbe.initialDelaySeconds`              | Initial delay seconds for probe                                                                                     | `15`                                                                             |
| `readinessProbe.periodSeconds`                    | Period seconds for probe                                                                                            | `60`                                                                             |
| `waitForIt.image.registry`                        | The OCI registry to pull the image from                                                                             | `cgr.dev`                                                                        |
| `waitForIt.image.repository`                      | The repository within the registry                                                                                  | `chainguard/wait-for-it`                                                         |
| `waitForIt.image.pullPolicy`                      | The image pull policy                                                                                               | `IfNotPresent`                                                                   |
| `waitForIt.image.version`                         | This value is deprecated in favor of tag. (Will be removed in a future release)                                     | `""`                                                                             |
| `waitForIt.image.tag`                             | Overrides the image tag whose default is the chart appVersion                                                       | `latest@sha256:5b836d1a4c652ec1c56bdd4a05a43349e2eeff50cf7fdb45a356f0ddc578573b` |
| `waitForIt.resources`                             | Resource requests and limits                                                                                        | `{}`                                                                             |
| `fsGroupFix.image.registry`                       | The OCI registry to pull the image from                                                                             | `cgr.dev`                                                                        |
| `fsGroupFix.image.repository`                     | The repository within the registry                                                                                  | `chainguard/bash`                                                                |
| `fsGroupFix.image.pullPolicy`                     | The image pull policy                                                                                               | `Always`                                                                         |
| `fsGroupFix.image.version`                        | This value is deprecated in favor of tag. (Will be removed in a future release)                                     | `""`                                                                             |
| `fsGroupFix.image.tag`                            | Overrides the image tag whose default is the chart appVersion                                                       | `latest@sha256:985a0c0ab82bd243bab1827fb48f8e11c8ec331391aad95d1a2f42b3810c1ec2` |
| `fsGroupFix.resources`                            | Specify resource needs as per https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/        | `{}`                                                                             |
| `workloadAttestors.unix.enabled`                  | Enables the Unix workload attestor                                                                                  | `false`                                                                          |
| `workloadAttestors.k8s.enabled`                   | Enables the Kubernetes workload attestor                                                                            | `true`                                                                           |
| `workloadAttestors.k8s.skipKubeletVerification`   | If true, kubelet certificate verification is skipped                                                                | `true`                                                                           |
| `workloadAttestors.k8s.disableContainerSelectors` | Set to true if using holdApplicationUntilProxyStarts in Istio                                                       | `false`                                                                          |
| `sds.enabled`                                     | Enables Envoy SDS configuration                                                                                     | `false`                                                                          |
| `sds.defaultSvidName`                             | The TLS Certificate resource name to use for the default X509-SVID with Envoy SDS                                   | `default`                                                                        |
| `sds.defaultBundleName`                           | The Validation Context resource name to use for the default X.509 bundle with Envoy SDS                             | `ROOTCA`                                                                         |
| `sds.defaultAllBundlesName`                       | The Validation Context resource name to use for all bundles (including federated) with Envoy SDS                    | `ALL`                                                                            |
| `sds.disableSpiffeCertValidation`                 | Disable Envoy SDS custom validation                                                                                 | `false`                                                                          |
| `telemetry.prometheus.enabled`                    | Flag to enable prometheus monitoring                                                                                | `false`                                                                          |
| `telemetry.prometheus.port`                       | Port for prometheus metrics                                                                                         | `9988`                                                                           |
| `telemetry.prometheus.podMonitor.enabled`         | Enable podMonitor for prometheus                                                                                    | `false`                                                                          |
| `telemetry.prometheus.podMonitor.namespace`       | Override where to install the podMonitor, if not set will use the same namespace as the spire-agent                 | `""`                                                                             |
| `telemetry.prometheus.podMonitor.labels`          | Pod labels to filter for prometheus monitoring                                                                      | `{}`                                                                             |
| `socketPath`                                      | The unix socket path to the spire-agent                                                                             | `/run/spire/agent-sockets/spire-agent.sock`                                      |
| `priorityClassName`                               | Priority class assigned to daemonset pods                                                                           | `""`                                                                             |
| `extraVolumes`                                    | Extra volumes to be mounted on Spire Agent pods                                                                     | `[]`                                                                             |
| `extraVolumeMounts`                               | Extra volume mounts for Spire Agent pods                                                                            | `[]`                                                                             |
| `extraContainers`                                 | Additional containers to create with Spire Agent pods                                                               | `[]`                                                                             |
| `initContainers`                                  | Additional init containers to create with Spire Agent pods                                                          | `[]`                                                                             |
| `hostAliases`                                     | Customize /etc/hosts file as described here https://kubernetes.io/docs/tasks/network/customize-hosts-file-for-pods/ | `[]`                                                                             |
| `customPlugins.keyManager`                        | Custom plugins of type KeyManager are configured here                                                               | `{}`                                                                             |
| `customPlugins.nodeAttestor`                      | Custom plugins of type NodeAttestor are configured here                                                             | `{}`                                                                             |
| `customPlugins.svidStore`                         | Custom plugins of type SVIDStore are configured here                                                                | `{}`                                                                             |
| `customPlugins.workloadAttestor`                  | Custom plugins of type WorkloadAttestor are configured here                                                         | `{}`                                                                             |
| `experimental.enabled`                            | Allow configuration of experimental features                                                                        | `false`                                                                          |
| `experimental.syncInterval`                       | Sync interval with SPIRE server with exponential backoff                                                            | `5s`                                                                             |
| `experimental.featureFlags`                       | List of developer feature flags                                                                                     | `[]`                                                                             |
