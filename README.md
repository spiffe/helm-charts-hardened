>  **Note**
> Things to consider:
> 1. We do not support running out of the git main branch. This is where development happens. Please use released versions via the published repo or git tags.
> 2. All the helm charts in this repo are beta. We encourage you to try them out and contribute. The API may change as we move towards a production ready release.

# SPIFFE Helm Charts

[![Apache 2.0 License](https://img.shields.io/github/license/spiffe/helm-charts)](https://opensource.org/licenses/Apache-2.0)
[![Development Phase](https://github.com/spiffe/spiffe/blob/main/.img/maturity/dev.svg)](https://github.com/spiffe/spiffe/blob/main/MATURITY.md#development)
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/spiffe)](https://artifacthub.io/packages/search?repo=spiffe)

A suite of [Helm Charts](https://helm.sh/docs) for standardized installations of SPIRE components in Kubernetes environments.

## How to install or upgrade

You most likely want to do an integrated setup based on the spire chart.
See the [Instructions](https://artifacthub.io/packages/helm/spiffe/spire#install-notes).

## Contributing

Before contributing ensure to check our [CONTRIBUTING](CONTRIBUTING.md) guidelines.

## LICENSE

This project is licensed under [Apache License, Version 2.0](LICENSE).

## Reporting a Vulnerability

Vulnerabilities can be reported by sending an email to security@spiffe.io. A confirmation email will be sent to acknowledge the report within 72 hours. A second acknowledgement will be sent within 7 days when the vulnerability has been positively or negatively confirmed.
