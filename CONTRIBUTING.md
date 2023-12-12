# CONTRIBUTING

:tada: Thanks for your interest in contributing to this project. In this document we outline a few guidelines to ease the way your contributions flow into this project.

## Contributor guidelines and Governance

Please see [CONTRIBUTING](https://github.com/spiffe/spiffe/blob/main/CONTRIBUTING.md) and [GOVERNANCE](https://github.com/spiffe/spiffe/blob/main/GOVERNANCE.md) from the SPIFFE project.

In addition to those guidelines we also have a couple guidelines specifically tailored to make your contributions as smooth as possible to contribute Helm charts.

## Prerequisites

- **Helm 3** or higher (<https://helm.sh/docs/intro/install/>)

## Commit style

Ensure you have clear and concise commits, written in the present tense. See [Kubernetes commit message guidelines](https://www.kubernetes.dev/docs/guide/pull-requests/#commit-message-guidelines) for a more detailed explanation of our approach.

```diff
+ git commit -m "Bump spire appVersion 1.4.4"
- git commit -m "Bumped spire appVersion 1.4.4"
```

## PRs

Stick with one feature/chart per branch. This allows us to make small controlled releases of the charts without blocking other chart releases in case of issues releasing a chart.

Ensure your branch is rebased on top of main before issuing your PR. This to keep a clean Git history and to ensure your changes are working with the latest main branch changes.

```bash
git checkout main
git pull
git checkout «your-branch»
git rebase main
```

## Testing

Our CI pipeline takes care of the majority of the testing of this Chart. Other ways for you to test are by running `make test` locally using:

> [!Warning]
> Ensure to run the test on a dedicated k8s cluster that does not have Spire installed yet.

```shell
make test
```

Another approach to testing the chart is by installing one of the examples in your own cluster to verify your contributed changes work before issueing your PR.

## Generating documentation

Any changes to Chart.yaml or values.yaml require an update of the README.md. This update can easily be generated using [readme-generator][].

```shell
./helm-docs.sh
```

## Bumping Chart version

In contrary to many other Helm repositories we do NOT require contributors to increate the Chart version. We have customized our release pipeline so we can bundle various PRs in a single release. Maintainers of the helm-charts in this repo will take care of the semantic versioning.

[readme-generator]: https://github.com/bitnami-labs/readme-generator-for-helm "Auto generate READMEs for Helm Charts."

## devcontainer support

We have a usable devcontainer with all the dev tools preinstalled to make contributions easier. You should be able to use it via Codespaces (https://github.com/codespaces/), Visual Studio Code (https://code.visualstudio.com/), DevPod (https://devpod.sh), etc. Please consult the documentation for those tools for how to use them.
