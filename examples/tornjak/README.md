# Recommended setup to deploy Tornjak

> **Warning**: The current version of Tornjak in this chart is deployed without authentication. Therefore it is not suitable to run this version in production.

To install Spire with the least privileges possible we deploy spire across 2 namespaces.

```shell
kubectl create namespace "spire-system"
kubectl label namespace "spire-system" pod-security.kubernetes.io/enforce=privileged
kubectl create namespace "spire-server"
kubectl label namespace "spire-server" pod-security.kubernetes.io/enforce=restricted

# deploy SPIRE with Tornjak enabled
helm upgrade --install --namespace spire-server \
  --values ../production/values.yaml \
  --values ./values.yaml \
  --render-subchart-notes \
  spire ../../charts/spire

# test the Tornjak deployment
helm test spire -n spire-server
```

## Access tornjak

To access Tornjak you will have to use port-forwarding for the time being *(until we add authentication and ingress)*.

Run following commands from your shell, if you ran with different values your namespace might differ. Consult the install notes printed when running above `helm upgrade` command in that case.

Since `port-forward` is a blocking command, execute them in two different consoles:

```shell
kubectl -n spire-server port-forward service/spire-tornjak-backend 10000:10000
```

```shell
kubectl -n spire-server port-forward service/spire-tornjak-frontend 3000:3000
```

You can now access Tornjak at [localhost:3000](http://localhost:3000).

See [values.yaml](./values.yaml) for more details on the chart configurations to achieve this setup.
