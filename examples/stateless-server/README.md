# Example stateless server

To install Spire Server as a deployment(stateless), you need to use an external database. This runs spire-server as stateless microservice enabling HA.

### WARNING
The following configurations are not supported for running spire-server as deployment.
1. spire-server.persistence.type
2. spire-server.dataStore.sql.databaseType: "sqlite3"
3. spire-server.keyManager.disk
4. spire-server.tornjak

If manually deploying for testing, you can create an incluster or use an external database and put the database password into an environment variable.

Next, edit your-values.yaml with your settings as described in the [production install instructions](https://artifacthub.io/packages/helm/spiffe/spire#production). Check it into your git repo if using one.

Then, deploy the chart pointing at your mysql instance like so:

```shell
helm upgrade --install --namespace spire-mgmt spire spire --repo https://spiffe.github.io/helm-charts-hardened/ -f examples/stateless-server/values.yaml --set "spire-server.dataStore.sql.password=${DBPW}" -f your-values.yaml
```

See the [production install instructions](https://artifacthub.io/packages/helm/spiffe/spire#production) for production recommendations.
See [values.yaml](./values.yaml) for more details on the chart configurations to achieve this setup.
