# spire-ha-agent

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.7.2](https://img.shields.io/badge/AppVersion-1.7.2-informational?style=flat-square)

A Helm chart to install the SPIRE HA agent.

**Homepage:** <https://github.com/spiffe/helm-charts-hardened/tree/main/charts/spire>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| marcofranssen | <marco.franssen@gmail.com> | <https://marcofranssen.nl> |
| kfox1111 | <Kevin.Fox@pnnl.gov> |  |
| faisal-memon | <fymemon@yahoo.com> |  |

## Source Code

* <https://github.com/spiffe/helm-charts-hardened/tree/main/charts/spire-ha-agent>

<!-- The parameters section is generated using helm-docs.sh and should not be edited by hand. -->

## Parameters

### Chart parameters

| Name                                          | Description                                                                                                         | Value                                                                            |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `image.registry`                              | The OCI registry to pull the image from                                                                             | `ghcr.io`                                                                        |
| `image.repository`                            | The repository within the registry                                                                                  | `spiffe/spire-ha-agent`                                                          |
| `image.pullPolicy`                            | The image pull policy                                                                                               | `IfNotPresent`                                                                   |
| `image.tag`                                   | Overrides the image tag whose default is the chart appVersion                                                       | `""`                                                                             |
| `singleSocket`                                | If in singleSocket mode, only one driver is used                                                                    | `false`                                                                          |
| `sockets.single.admin.hostPath`               | Where the sockets are on disk when in single socket mode                                                            | `/var/run/spire/agent/sockets/main/csi.spiffe.io/admin`                          |
| `sockets.a.admin.hostPath`                    | Where the sockets are on disk                                                                                       | `/var/run/spire/agent/sockets/a/csi.spiffe.io/admin`                             |
| `sockets.b.admin.hostPath`                    | Where the sockets are on disk                                                                                       | `/var/run/spire/agent/sockets/b/csi.spiffe.io/admin`                             |
| `vsock`                                       | Use a vsockets to expose the service rather then a unix socket                                                      | `false`                                                                          |
| `port`                                        | Port number to listen on                                                                                            | `999`                                                                            |
| `imagePullSecrets`                            | Pull secrets for images                                                                                             | `[]`                                                                             |
| `nameOverride`                                | Name override                                                                                                       | `""`                                                                             |
| `namespaceOverride`                           | Namespace override                                                                                                  | `""`                                                                             |
| `fullnameOverride`                            | Fullname override                                                                                                   | `""`                                                                             |
| `serviceAccount.create`                       | Specifies whether a service account should be created                                                               | `true`                                                                           |
| `serviceAccount.annotations`                  | Annotations to add to the service account                                                                           | `{}`                                                                             |
| `serviceAccount.name`                         | The name of the service account to use.                                                                             | `""`                                                                             |
| `podAnnotations`                              | Annotations to add to pods                                                                                          | `{}`                                                                             |
| `podLabels`                                   | Labels to add to pods                                                                                               | `{}`                                                                             |
| `podSecurityContext`                          | Pod security context                                                                                                | `{}`                                                                             |
| `securityContext`                             | Security context                                                                                                    | `{}`                                                                             |
| `resources`                                   | Resource requests and limits                                                                                        | `{}`                                                                             |
| `nodeSelector`                                | Node selector                                                                                                       | `{}`                                                                             |
| `tolerations`                                 | List of tolerations                                                                                                 | `[]`                                                                             |
| `affinity`                                    | Node affinity                                                                                                       | `{}`                                                                             |
| `updateStrategy.type`                         | The update strategy to use to replace existing DaemonSet pods with new pods. Can be RollingUpdate or OnDelete.      | `RollingUpdate`                                                                  |
| `updateStrategy.rollingUpdate.maxUnavailable` | Max unavailable pods during update. Can be a number or a percentage.                                                | `1`                                                                              |
| `fsGroupFix.image.registry`                   | The OCI registry to pull the image from                                                                             | `cgr.dev`                                                                        |
| `fsGroupFix.image.repository`                 | The repository within the registry                                                                                  | `chainguard/bash`                                                                |
| `fsGroupFix.image.pullPolicy`                 | The image pull policy                                                                                               | `Always`                                                                         |
| `fsGroupFix.image.tag`                        | Overrides the image tag whose default is the chart appVersion                                                       | `latest@sha256:e16830b0cc7e9e3258588fbcb82714ee67d9043221632832d7504080151bb1d2` |
| `fsGroupFix.resources`                        | Specify resource needs as per https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/        | `{}`                                                                             |
| `cid2PID.image.registry`                      | The OCI registry to pull the image from                                                                             | `ghcr.io`                                                                        |
| `cid2PID.image.repository`                    | The repository within the registry                                                                                  | `kfox1111/cid2pid`                                                               |
| `cid2PID.image.pullPolicy`                    | The image pull policy                                                                                               | `Always`                                                                         |
| `cid2PID.image.tag`                           | Overrides the image tag whose default is the chart appVersion                                                       | `v0.0.3`                                                                         |
| `cid2PID.busybox.image.registry`              | The OCI registry to pull the image from                                                                             | `docker.io`                                                                      |
| `cid2PID.busybox.image.repository`            | The repository within the registry                                                                                  | `library/busybox`                                                                |
| `cid2PID.busybox.image.pullPolicy`            | The image pull policy                                                                                               | `IfNotPresent`                                                                   |
| `cid2PID.busybox.image.tag`                   | Overrides the image tag whose default is the chart appVersion                                                       | `1.36.1-uclibc`                                                                  |
| `cid2PID.busybox.resources`                   | Specify resource needs as per https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/        | `{}`                                                                             |
| `socketPath`                                  | The unix socket path to the spire-agent                                                                             | `/run/spire/agent-sockets/spire-agent.sock`                                      |
| `socketAlternate.names`                       | List of alternate names for the socket that workloads might expect to be able to access in the driver mount.        | `["socket","spire-agent.sock","api.sock"]`                                       |
| `socketAlternate.image.registry`              | The OCI registry to pull the image from                                                                             | `cgr.dev`                                                                        |
| `socketAlternate.image.repository`            | The repository within the registry                                                                                  | `chainguard/bash`                                                                |
| `socketAlternate.image.pullPolicy`            | The image pull policy                                                                                               | `Always`                                                                         |
| `socketAlternate.image.tag`                   | Overrides the image tag whose default is the chart appVersion                                                       | `latest@sha256:e16830b0cc7e9e3258588fbcb82714ee67d9043221632832d7504080151bb1d2` |
| `socketAlternate.resources`                   | Specify resource needs as per https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/        | `{}`                                                                             |
| `priorityClassName`                           | Priority class assigned to daemonset pods. Can be auto set with global.recommendations.priorityClassName.           | `""`                                                                             |
| `extraEnvVars`                                | Extra environment variables to be added to the Spire Agent container                                                | `[]`                                                                             |
| `extraVolumes`                                | Extra volumes to be mounted on Spire Agent pods                                                                     | `[]`                                                                             |
| `extraVolumeMounts`                           | Extra volume mounts for Spire Agent pods                                                                            | `[]`                                                                             |
| `extraContainers`                             | Additional containers to create with Spire Agent pods                                                               | `[]`                                                                             |
| `initContainers`                              | Additional init containers to create with Spire Agent pods                                                          | `[]`                                                                             |
| `hostAliases`                                 | Customize /etc/hosts file as described here https://kubernetes.io/docs/tasks/network/customize-hosts-file-for-pods/ | `[]`                                                                             |
