# Deploy Tornjak with Authentication Enabled

This example demonstrates Tornjak's capability to control access to the Frontend Application using
User Management via [Keycloak](https://www.keycloak.org/).

For more information regarding Tornjak User Management, please refer to the following documentation:

* [Tornjak User Management](https://github.com/spiffe/tornjak/blob/main/docs/keycloak-configuration.md)
* [Keycloak Configuration for Tornjak](https://github.com/spiffe/tornjak/blob/main/docs/keycloak-configuration.md)
* [Detailed Blogs on Tornjak User Management](https://github.com/spiffe/tornjak/blob/main/docs/blogs.md)

**NOTE:** This example works only with the Vanilla version of Kubernetes; it does not yet support Openshift.

As part of the exercise, an instance of Keycloak is deployed to illustrate how to manage users' access to Tornjak.
Once enabled, the Tornjak UI will redirect all authentication calls to the Keycloak instance to obtain the
correct credentials. Authorization is based on these credentials and occurs at the Tornjak application level.

## Deploy Keycloak Instance (Authentication Service)

We will deploy the instance of Keycloak in the same namespace as the SPIRE Server

```shell
# Create a namespace to deploy Keycloak and SPIRE-server
kubectl create namespace spire-server
```

```shell
# Create a secret from the realm JSON file for Tornjak realm import
kubectl create secret generic realm-secret -n spire-server --from-file=examples/tornjak/keycloak/tornjak-realm.json
```

```shell
# Deploy Keycloak as an authentication service
helm upgrade --install -n spire-server keycloak --values examples/tornjak/keycloak/values.yaml oci://registry-1.docker.io/bitnamicharts/keycloak --render-subchart-notes
```

## Deploy SPIRE with Tornjak User Management Enabled

Please follow the instructions for deploying Tornjak as specified in Tornjak Example [here](../README.md)
with addition of the User Management values `--values examples/tornjak/values-auth.yaml`.

For example:

```shell
# Standard SPIRE and Tornjak deployment with Authentication enabled
helm upgrade --install \
--set global.spire.namespaces.system.create=true \
--values examples/production/values.yaml \
--values examples/production/example-your-values.yaml \
--values examples/tornjak/values.yaml \
--values examples/tornjak/values-auth.yaml \
--render-subchart-notes spire charts/spire
```

To test the deployment, you can run the SPIRE test:

```shell
# Test the Tornjak deployment
helm test spire
```

## Access Tornjak

To access Tornjak use port-forwarding or check the ingress option below.

Run following commands from your shell, if you run with different values your namespace might differ. Consult the install notes printed when running above `helm upgrade` command in that case.

Since `port-forward` is a blocking command, execute them in three different consoles (one for backend, one for frontend and one for auth):

* Backend Service (Terminal 1)

```shell
kubectl -n spire-server port-forward service/spire-tornjak-backend 10000:10000
```

* Frontend Service (Terminal 2)

```shell
kubectl -n spire-server port-forward service/spire-tornjak-frontend 3000:3000
```

* Auth Service [Keycloak] (Terminal 3)

```shell
kubectl -n spire-server port-forward service/keycloak 8080:80
```

You can now access Tornjak at [localhost:3000](http://localhost:3000).

This will redirect to the auth service for authentication [localhost:8080](http://localhost:8080)

See [values.yaml](./values.yaml) for more details on the chart configurations to customize authentication config.

## Deploy SPIRE with Tornjak User Management Enabled using Ingress

When deployment uses Ingress, the access to Tornjak application and Keycloak will be different from above.
Please follow the deployment and configuration instructions as described [here](../README.md)
and make sure to add the `--values examples/tornjak/values-auth.yaml` parameter that is referencing Tornjak Authentication values.

And update your `examples/production/example-your-values.yaml` most importantly, `trustDomain`, accordingly.

E.g:

```shell
helm upgrade --install \
--set global.spire.namespaces.create=true \
--set global.spire.ingressControllerType=ingress-nginx \
--values examples/production/values.yaml \
--values examples/production/example-your-values.yaml \
--values examples/tornjak/values.yaml \
--values examples/tornjak/values-auth.yaml \
--values examples/tornjak/values-ingress.yaml \
--render-subchart-notes spire charts/spire
```
