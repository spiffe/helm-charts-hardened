# spire-tcp-broker

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.15.1](https://img.shields.io/badge/AppVersion-1.15.1-informational?style=flat-square)

A Helm chart to install a dedicated SPIRE agent exposing the SPIFFE Broker API over TCP.

**Homepage:** <https://github.com/spiffe/helm-charts-hardened/tree/main/charts/spire-tcp-broker>


## Maintainers

| Name | Email | Url |
| ---- | ----- | --- |
| marcofranssen | <marco.franssen@gmail.com> | <https://marcofranssen.nl> |
| kfox1111 | <Kevin.Fox@pnnl.gov> |  |
| faisal-memon | <fymemon@yahoo.com> |  |
| matheuscscp | <matheuscscp@linux.com> |  |

## Source Code

* <https://github.com/spiffe/helm-charts-hardened/tree/main/charts/spire-tcp-broker>

<!-- The parameters section is generated using helm-docs.sh and should not be edited by hand. -->

## Parameters

### Chart parameters

| Name                                 | Description                                                                                                                                           | Value                |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------- |
| `image.registry`                     | The OCI registry to pull the image from                                                                                                               | `ghcr.io`            |
| `image.repository`                   | The repository within the registry                                                                                                                    | `spiffe/spire-agent` |
| `image.pullPolicy`                   | The image pull policy                                                                                                                                 | `IfNotPresent`       |
| `image.tag`                          | Overrides the image tag whose default is the chart appVersion                                                                                         | `""`                 |
| `imagePullSecrets`                   | Pull secrets for images                                                                                                                               | `[]`                 |
| `nameOverride`                       | Name override                                                                                                                                         | `""`                 |
| `fullnameOverride`                   | Fullname override                                                                                                                                     | `""`                 |
| `replicas`                           | Number of SPIRE broker agent replicas                                                                                                                 | `1`                  |
| `serviceAccount.annotations`         | Annotations to add to the service account                                                                                                             | `{}`                 |
| `configMap.annotations`              | Annotations to add to the SPIRE Broker Agent ConfigMap                                                                                                | `{}`                 |
| `podAnnotations`                     | Annotations to add to pods                                                                                                                            | `{}`                 |
| `podLabels`                          | Labels to add to pods                                                                                                                                 | `{}`                 |
| `podSecurityContext`                 | Pod security context                                                                                                                                  | `{}`                 |
| `securityContext`                    | Security context                                                                                                                                      | `{}`                 |
| `resources`                          | Resource requests and limits for the spire-agent container                                                                                            | `{}`                 |
| `nodeSelector`                       | Node selector                                                                                                                                         | `{}`                 |
| `tolerations`                        | List of tolerations                                                                                                                                   | `[]`                 |
| `affinity`                           | Node affinity                                                                                                                                         | `{}`                 |
| `priorityClassName`                  | Priority class assigned to deployment pods. Can be auto set with global.recommendations.priorityClassName.                                            | `""`                 |
| `logLevel`                           | The log level, valid values are "debug", "info", "warn", and "error"                                                                                  | `info`               |
| `logFormat`                          | The log format, valid values are "text" and "json"                                                                                                    | `text`               |
| `clusterName`                        | Name of the pod-agent cluster configured in the SPIRE server k8s_psat node attestor                                                                   | `""`                 |
| `trustDomain`                        | The trust domain to be used for the SPIFFE identifiers                                                                                                | `example.org`        |
| `trustBundleURL`                     | If set, obtain trust bundle from url instead of Kubernetes ConfigMap                                                                                  | `""`                 |
| `trustBundleFormat`                  | If using trustBundleURL, what format is the url. Choices are "pem" and "spiffe"                                                                       | `spiffe`             |
| `bundleConfigMap`                    | Configmap name for Spire bundle                                                                                                                       | `spire-bundle`       |
| `rebootstrapMode`                    | How the agent will behave when seeing an unknown x509 cert from the server. It can be set to never, auto, or always                                   | `always`             |
| `rebootstrapDelay`                   | The agent will rebootstrap after configured amount of time on unknown x509 cert from the server                                                       | `10m`                |
| `server.address`                     | Address of the SPIRE server service                                                                                                                   | `""`                 |
| `server.port`                        | Port number for Spire server                                                                                                                          | `443`                |
| `healthChecks.port`                  | Port where health checks are exposed                                                                                                                  | `9983`               |
| `livenessProbe.initialDelaySeconds`  | Initial delay seconds for probe                                                                                                                       | `15`                 |
| `livenessProbe.periodSeconds`        | Period seconds for probe                                                                                                                              | `60`                 |
| `readinessProbe.initialDelaySeconds` | Initial delay seconds for probe                                                                                                                       | `10`                 |
| `readinessProbe.periodSeconds`       | Period seconds for probe                                                                                                                              | `30`                 |
| `service.type`                       | Service type                                                                                                                                          | `ClusterIP`          |
| `service.port`                       | Service port for the Broker API                                                                                                                       | `8443`               |
| `service.annotations`                | Annotations for service resource                                                                                                                      | `{}`                 |
| `controllerManagerClassName`         | SPIRE Controller Manager class name that reconciles the agent alias                                                                                   | `""`                 |
| `workloadAgentAlias`                 | SPIFFE ID of the agent alias that parents the Broker ClusterStaticEntries                                                                             | `""`                 |
| `brokers`                            | Named Brokers allowed to use the Broker API over TCP. namespace defaults to the release namespace and serviceAccountName defaults to the Broker name. | `[]`                 |
| `staticEntries`                      | Static entries parented by this Broker agent's alias. path is relative to the trust domain and selectors are passed to the ClusterStaticEntry.        | `[]`                 |
| `extraEnvVars`                       | Extra environment variables to be added to the Spire Agent container                                                                                  | `[]`                 |
| `extraVolumes`                       | Extra volumes to be mounted on Spire Agent pods                                                                                                       | `[]`                 |
| `extraVolumeMounts`                  | Extra volume mounts for Spire Agent pods                                                                                                              | `[]`                 |
| `extraContainers`                    | Additional containers to create with Spire Agent pods                                                                                                 | `[]`                 |
| `initContainers`                     | Additional init containers to create with Spire Agent pods                                                                                            | `[]`                 |
