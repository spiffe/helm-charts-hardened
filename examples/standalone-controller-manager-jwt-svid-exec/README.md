# Standalone controller manager with jwtSVIDExec kubeConfigs

End-to-end exercise of `jwtSVIDExec`-based `kubeConfigs` entries combined with `spire-server.controllerManager.deploymentMode: standalone`. This is a companion to [`examples/standalone-controller-manager/`](../standalone-controller-manager/), which covers the basic standalone deployment without any external kubeConfigs.

## What this exercises

- A **source** kind cluster runs SPIRE with `controllerManager.deploymentMode: standalone`, exposing its `spiffe-oidc-discovery-provider` behind ingress-nginx so the target cluster's apiserver can fetch its issuer document and JWK set.
- A **target** kind cluster is created inside `run-tests.sh` with an `AuthenticationConfiguration` pointing at the source cluster's OIDC discovery URL as the issuer. A `ClusterRoleBinding` grants `cluster-admin` to the SPIFFE ID configured via `jwtSVIDExecConfig.spiffeID`.
- The source cluster's SPIRE install is then reconfigured with a `kubeConfigs.target` entry using `jwtSVIDExec`. The chart wires the exec plugin to source its JWT-SVID from the standalone Pod's own in-pod agent (`workload-api` mode), and materializes `jwtSVIDExecConfig.spiffeID` as an extra static bootstrap workload entry (non-admin, `unix:path` on the plugin binary, hint-tagged) parented to the standalone Pod's node-alias.
- A marker Pod on the target cluster plus a `ClusterSPIFFEID` applied to the target cluster produce the observable: the source SPIRE Server ends up with a registration entry reconciled by the standalone Pod's per-target CM Deployment, which only happens if the exec plugin successfully minted a JWT-SVID via its own agent's Workload API and the target apiserver accepted it.

## Requirements

- A `spire-controller-manager` image build that supports connecting to the SPIRE Server over TCP (the `spireServerAddress`/`workloadAPIAddr` configuration fields). Until a release with this support is published upstream, override `spire-server.controllerManager.image` with a compatible build.
- Kubernetes 1.34+ on the target cluster (structured authentication configuration is GA in 1.34). On 1.33 the target kind config enables the `StructuredAuthenticationConfiguration` feature gate; older versions are not supported by this example.

## Running

The example is auto-picked-up by the CI example matrix. Locally:

```shell
K8S=v1.34.3 ./run-tests.sh
```

Pass `-c` to skip cluster/release teardown for inspection after the run.

## Files

- `values.yaml` — source cluster values; `kubeConfigs.target.jwtSVIDExec.server` and `.certificateAuthorityData` are placeholders overridden by `run-tests.sh` via `--set` once the target cluster is up.
- `target-workload.yaml` — the marker Pod and its labeled namespace, applied to the target cluster.
- `cluster-spiffe-id.yaml` — the `ClusterSPIFFEID` applied to the target cluster; matches the marker Pod's namespace/labels.
- `.test-files/target-kind-config.yaml.tmpl` — kind config for the target cluster; enables the structured-authn feature gate and mounts `/etc/kubernetes/pki/authn` from a host directory populated by `run-tests.sh`.
- `.test-files/authentication-config.yaml.tmpl` — target apiserver `AuthenticationConfiguration` template; `__ISSUER_URL__` is substituted by `run-tests.sh`.
- `.test-files/target-rbac.yaml` — `ClusterRoleBinding` granting `cluster-admin` to the SPIFFE ID configured via `jwtSVIDExecConfig.spiffeID`.

## Not covered

- Bundle rotation on the source cluster during the test window. SPIRE rotates JWT signing keys; a very long CI run could see the target apiserver's cached JWKs become stale between successive exec-credential invocations. The apiserver refetches the JWK set on validation failure, so this is self-healing but adds latency.
- The dual-consumer conflict path (where the same `kubeConfigs` entry would be consumed by both a standalone controller-manager and an enabled spire-server-container consumer such as `nodeAttestor.externalK8sPSAT`). That's covered by the chart's render-time `fail` and the corresponding unit test in `tests/unit/spire_test.go`.
