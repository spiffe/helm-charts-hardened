# Standalone controller manager

By default the SPIRE Controller Manager runs as an additional container inside the `spire-server` Pod, sharing spire-server's local admin API socket. Because Kubernetes only considers a Pod `Ready` when *every* container in it reports ready, a controller-manager failure (e.g. leader election churn, a cache sync timeout) can flip the whole `spire-server` Pod to `NotReady`, pulling it out of the Service used by agents for the workload API - even though spire-server itself is healthy. See [#341](https://github.com/spiffe/helm-charts-hardened/issues/341).

Setting `spire-server.controllerManager.deploymentMode: standalone` moves the controller manager out of the spire-server Pod into its own Deployment, connecting to the SPIRE Server over TCP using SPIFFE mTLS instead of the local Unix domain socket. The Deployment carries its own in-pod `spire-agent` sidecar, attested as a distinct k8s_psat "node" scoped to its own ServiceAccount, so it obtains its own SPIFFE identity without depending on the per-node `spiffe-csi-driver`/agent DaemonSet. Its bootstrap identity (a node-alias plus an admin workload entry) is fully static and applied by a `postStart` hook on the `spire-server` container, so it never affects the `spire-server` Pod's readiness and works regardless of `staticManifestMode`.

## Requirements

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
