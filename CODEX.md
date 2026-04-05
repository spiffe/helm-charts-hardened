# CODEX

This file is a lightweight working guide for Codex and human contributors in this repository.

## Repo Overview

- Main charts live in `charts/`
- The integrated SPIRE chart is `charts/spire`
- Supporting charts include `charts/spire-crds`, `charts/spire-ha-agent`, `charts/spiffe-step-ssh`, and subcharts under `charts/spire/charts/`
- Example installs and scenario configs live in `examples/`
- Go-based unit tests live in `tests/unit`
- Cluster-backed integration tests live in `tests/integration`

## Common Commands

- `make lint`
  - Runs chart-testing lint using `ct.yaml`
- `cd tests/unit && ginkgo`
  - Runs Go unit/render tests for Helm templates
- `make test`
  - Runs chart tests and example tests against a dedicated Kubernetes cluster
- `./helm-docs.sh`
  - Regenerates chart README files after `Chart.yaml` or `values.yaml` changes

## Working Agreements

- Do not bump chart versions as part of normal contributions; maintainers handle release versioning
- If you change `Chart.yaml` or `values.yaml`, regenerate docs with `./helm-docs.sh`
- Prefer focused changes to a single chart or feature area per branch
- Preserve existing Helm templating patterns and values structure unless the task requires a broader refactor
- When possible, validate template changes with `cd tests/unit && ginkgo` before broader cluster tests

## Testing Notes

- `make test` assumes access to a dedicated Kubernetes cluster
- CI also runs Kind-based install tests and example matrices from `.github/workflows/helm-chart-ci.yaml`
- Unit tests render the `charts/spire` chart directly and assert against generated template output

## Useful Paths

- `README.md`
- `CONTRIBUTING.md`
- `.github/workflows/helm-chart-ci.yaml`
- `ct.yaml`
- `charts/spire/`
- `tests/unit/spire_test.go`

## Editing Guidance

- Keep generated README sections in sync by rerunning `./helm-docs.sh`
- Avoid hardcoded image references in templates; CI checks for overridable image templating
- Be careful with changes that affect nested charts, examples, or appVersion alignment across subcharts
