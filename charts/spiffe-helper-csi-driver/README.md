# spire-helper-csi-driver

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.7.2](https://img.shields.io/badge/AppVersion-1.7.2-informational?style=flat-square)

A Helm chart to install the SPIFFE HELPER CSI Driver.

**Homepage:** <https://github.com/spiffe/helm-charts/tree/main/charts/spire>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| marcofranssen | <marco.franssen@gmail.com> | <https://marcofranssen.nl> |
| kfox1111 | <Kevin.Fox@pnnl.gov> |  |
| faisal-memon | <fymemon@yahoo.com> |  |
| edwbuck | <edwbuck@gmail.com> |  |

## Source Code

* <https://github.com/spiffe/helm-charts/tree/main/charts/spiffe-helpe-csi-driver>

## Prereqs:

Your cluster needs to have Kyverno installed. You can do that by running something like the following:

```
helm upgrade --install --create-namespace kyverno kyverno -n kyverno --repo https://kyverno.github.io/kyverno/ --version 3.1.1
```

You also need SPIRE installed. You can do that by running something like the following for a non production test cluster:

```
helm install -n spire-server spire-crds spire-crds --repo https://spiffe.github.io/helm-charts-hardened/ --create-namespace
helm install -n spire-server spire spire --repo https://spiffe.github.io/helm-charts-hardened/
```

## Build Instructions

Until there is an official release of this chart, before you can use it out of git, you have to run
```
cd charts/spiffe-helper-csi-driver
helm dep up
```

## Install Instructions
```
helm install -n spire-server spiffe-helper-csi-driver charts/spiffe-helper-csi-driver
```

## Example usage

See the examples/good directory for different ways of using the driver.

<!-- The parameters section is generated using helm-docs.sh and should not be edited by hand. -->

## Parameters
