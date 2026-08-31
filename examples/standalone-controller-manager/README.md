# Standalone controller manager

By default the SPIRE Controller Manager runs as an additional container inside the `spire-server` Pod, sharing spire-server's local admin API socket. Because Kubernetes only considers a Pod `Ready` when *every* container in it reports ready, a controller-manager failure (e.g. leader election churn, a cache sync timeout) can flip the whole `spire-server` Pod to `NotReady`, pulling it out of the Service used by agents for the workload API - even though spire-server itself is healthy. See [#341](https://github.com/spiffe/helm-charts-hardened/issues/341).

Setting `spire-server.controllerManager.deploymentMode: standalone` moves the controller manager out of the spire-server Pod into its own Deployment, connecting to the SPIRE Server over TCP using SPIFFE mTLS instead of the local Unix domain socket. A minimal "bootstrap" container is still deployed alongside spire-server - its only job is to grant the standalone Deployment its own SPIFFE identity, and it has no `readinessProbe`, so it never affects the spire-server Pod's readiness.

## Requirements

- The `spiffe-csi-driver` chart must be enabled (it is by default) so the standalone Deployment can obtain its own SPIFFE Workload API access, the same way any other workload does.
- A `spire-controller-manager` image build that supports connecting to the SPIRE Server over TCP (the `spireServerAddress`/`workloadAPIAddr` configuration fields). Until a release with this support is published upstream, override `spire-server.controllerManager.image` with a compatible build.

## Deploy

```shell
helm upgrade --install -n spire-server spire spire \
  --repo https://spiffe.github.io/helm-charts-hardened/ \
  --values examples/standalone-controller-manager/values.yaml \
  --values your-values.yaml
```

## Validation

Confirm the controller manager is running as its own Deployment, separate from the `spire-server` StatefulSet:

```shell
kubectl get deployment -n spire-server spire-controller-manager-standalone
```

Deploy a plain workload elsewhere in the cluster and confirm it receives a SPIFFE ID, proving the standalone Deployment is reconciling ordinary `ClusterSPIFFEID`s (not just its own bootstrap identity) over its TCP connection to spire-server:

```shell
kubectl apply -f examples/standalone-controller-manager/client-pod.yaml
kubectl logs standalone-cm-client -f
```

You should see output similar to:

```text
Received 1 svid after 10s

SPIFFE ID:		spiffe://<trust domain>/ns/default/sa/default
```
