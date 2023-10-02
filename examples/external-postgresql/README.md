# Example external postgresql

We recommend you put your config into git, but never put a password directly into git. Generally the easiest way to do so is via
environment variable. Your CI/CD system of choice usually allows you to set those. Please refer to your systems documentation for
guidance.

If manually deploying for testing, you can safely put the password into an environment variable by running:

```bash
source ../bin/readpw.sh
```

Next, edit values.yaml with your settings. Check it into your git repo if using one.

Then, deploy the chart pointing at your postgresql instance like so:

```shell
helm upgrade --install --namespace spire-server spire charts/spire -f values.yaml --set "spire-server.dataStore.sql.password=${DBPW}"

```

See the [production example](../production) for production recommendations.
See [values.yaml](./values.yaml) for more details on the chart configurations to achieve this setup.
