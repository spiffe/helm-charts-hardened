# Example external mysql

We recommend you put your config into git, but never put a password directly into git. Generally the easiest way to do so is via
environment variable. Your CI/CD system of choice usually allows you to set those. Please refer to your systems documentation for
guidance.

If manually deploying for testing, you can safely put the password into an environment variable by running:

```bash
source ../bin/readpw.sh
```

Follow the instructions as described at https://artifacthub.io/packages/helm/spiffe/spire, and copy in the settings from
examples/external-mysql/values.yaml into your values file.

You can add the password at install runtime like so:

```shell
helm upgrade --install --namespace spire-mgmt spire spire -f your-values.yaml --set "spire-server.dataStore.sql.password=${DBPW}" --repo https://spiffe.github.io/helm-charts-hardened/
```
