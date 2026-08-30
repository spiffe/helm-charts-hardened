# spiffefs

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.4.0](https://img.shields.io/badge/AppVersion-0.4.0-informational?style=flat-square)

A Helm chart to install spiffefs, a FUSE filesystem that delivers SPIFFE X.509 credentials to workloads as files.

**Homepage:** <https://github.com/spiffe/helm-charts-hardened/tree/main/charts/spiffefs>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| marcofranssen | <marco.franssen@gmail.com> | <https://marcofranssen.nl> |
| kfox1111 | <Kevin.Fox@pnnl.gov> |  |
| faisal-memon | <fymemon@yahoo.com> |  |

## Source Code

* <https://github.com/spiffe/spiffefs>

## Requirements

Kubernetes: `>=1.21.0-0`

| Repository | Name | Version |
|------------|------|---------|
| file://../spire-lib | spire-lib | 0.3.1 |

## Usage

spiffefs runs as a DaemonSet and mounts a FUSE filesystem on the host. A
`spiffe-csi-driver` instance then publishes that directory to workloads, which
read their credentials as ordinary files rather than speaking the Workload API.

It reaches SPIRE over the agent's admin socket, using the Delegated Identity
API, and it finds that socket on the host. The agent has to be told to put it
there — this chart cannot do that for you:

```yaml
spire-agent:
  sockets:
    admin:
      enabled: true
      mountOnHost: true
```

The simplest way to deploy it is through the `spire` chart, which wires up both
this chart and a matching CSI driver instance when `spiffefs.enabled` is set.
See `examples/spiffefs` for a working configuration.

The CSI driver publishes the *parent* of `mountPath`, so workloads read the files
one level down — `<volume mountPath>/private/credential-bundle.private-key.x509.pem`
with the default settings. Publishing the mount point itself would tie a workload to
a single filesystem instance, which is orphaned as soon as spiffefs restarts.

A workload consuming the filesystem should set `mountPropagation:
HostToContainer` on its volume mount, so that spiffefs remounting on restart
reaches it instead of leaving a stale mount behind.

<!-- The parameters section is generated using helm-docs.sh and should not be edited by hand. -->

## Parameters

### spiffefs chart parameters

| Name                                          | Description                                                                                                                                                                                                                 | Value                                                     |
| --------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| `image.registry`                              | The OCI registry to pull the image from                                                                                                                                                                                     | `ghcr.io`                                                 |
| `image.repository`                            | The repository within the registry                                                                                                                                                                                          | `spiffe/spiffefs`                                         |
| `image.pullPolicy`                            | The image pull policy                                                                                                                                                                                                       | `IfNotPresent`                                            |
| `image.tag`                                   | Overrides the image tag whose default is the chart appVersion                                                                                                                                                               | `""`                                                      |
| `mountPath`                                   | Host directory spiffefs mounts its filesystem on. Its parent is what the spiffe-csi-driver instance publishes, so workloads read the files one level down. The parent must match that instance's agentSocketPath directory. | `/run/spire/k8s/spiffefs/private`                         |
| `agentSocketPath`                             | Host path to the spire-agent admin socket used for the Delegated Identity API. Requires the agent to set sockets.admin.enabled and sockets.admin.mountOnHost.                                                               | `/run/spire/agent/sockets/csi.spiffe.io/admin/admin.sock` |
| `updateStrategy.type`                         | The update strategy to use to replace existing DaemonSet pods with new pods. Can be RollingUpdate or OnDelete.                                                                                                              | `RollingUpdate`                                           |
| `updateStrategy.rollingUpdate.maxUnavailable` | Max unavailable pods during update. Can be a number or a percentage.                                                                                                                                                        | `1`                                                       |
| `readinessProbe.initialDelaySeconds`          | Initial delay seconds for the readiness probe                                                                                                                                                                               | `2`                                                       |
| `readinessProbe.periodSeconds`                | How often to check that the filesystem is still mounted                                                                                                                                                                     | `5`                                                       |
| `readinessProbe.timeoutSeconds`               | Timeout value in seconds for the readiness probe                                                                                                                                                                            | `2`                                                       |
| `resources`                                   | Resource requests and limits for spiffefs                                                                                                                                                                                   | `{}`                                                      |
| `extraEnvVars`                                | Extra environment variables to be added to the spiffefs container                                                                                                                                                           | `[]`                                                      |
| `initContainers`                              | Init containers to add to the spiffefs DaemonSet                                                                                                                                                                            | `[]`                                                      |
| `extraContainers`                             | Extra containers to add to the spiffefs DaemonSet                                                                                                                                                                           | `[]`                                                      |
| `extraVolumes`                                | Extra volumes to add to the spiffefs DaemonSet                                                                                                                                                                              | `[]`                                                      |
| `extraVolumeMounts`                           | Extra volume mounts to add to the spiffefs container                                                                                                                                                                        | `[]`                                                      |
| `imagePullSecrets`                            | Image pull secret details for spiffefs                                                                                                                                                                                      | `[]`                                                      |
| `nameOverride`                                | Name override for spiffefs                                                                                                                                                                                                  | `""`                                                      |
| `fullnameOverride`                            | Full name override for spiffefs                                                                                                                                                                                             | `""`                                                      |
| `namespaceOverride`                           | Namespace to install spiffefs into                                                                                                                                                                                          | `""`                                                      |
| `serviceAccount.create`                       | Specifies whether a service account should be created                                                                                                                                                                       | `true`                                                    |
| `serviceAccount.annotations`                  | Annotations to add to the service account                                                                                                                                                                                   | `{}`                                                      |
| `serviceAccount.name`                         | The name of the service account to use. If not set and create is true, a name is generated.                                                                                                                                 | `""`                                                      |
| `podAnnotations`                              | Pod annotations for spiffefs                                                                                                                                                                                                | `{}`                                                      |
| `podLabels`                                   | Labels to add to pods                                                                                                                                                                                                       | `{}`                                                      |
| `securityContext`                             | Security context for the spiffefs container. Mounting FUSE and reading caller pids requires privileged and root.                                                                                                            | `{}`                                                      |
| `nodeSelector`                                | Node selector for spiffefs pods                                                                                                                                                                                             | `{}`                                                      |
| `tolerations`                                 | Tolerations for spiffefs pods                                                                                                                                                                                               | `[]`                                                      |
| `affinity`                                    | Node affinity                                                                                                                                                                                                               | `{}`                                                      |
| `priorityClassName`                           | Priority class assigned to daemonset pods. Can be auto set with global.recommendations.priorityClassName.                                                                                                                   | `""`                                                      |

