# Deploy Tornjak with Authentication Enabled

This example demonstrates Tornjak's capability to control access to the Frontend Application using
User Management via [Keycloak](https://www.keycloak.org/).

Tested on:

- Keycloak Application Version - 24.0.3
- Keycloak Chart Version - 21.0.3

For more information regarding Tornjak User Management, please refer to the following documentation:

- [Tornjak User Management](https://github.com/spiffe/tornjak/blob/main/docs/user-management.md)
- [Keycloak Configuration for Tornjak](https://github.com/spiffe/tornjak/blob/main/docs/keycloak-configuration.md)
- [Detailed Blogs on Tornjak User Management](https://github.com/spiffe/tornjak/blob/main/docs/blogs.md)

> [!NOTE]
> This example works only with the Vanilla version of Kubernetes; it does not yet support Openshift.

As part of the exercise, an instance of Keycloak is deployed to illustrate how to manage users' access to Tornjak.
Once enabled, the Tornjak UI will redirect all authentication calls to the Keycloak instance to obtain the
correct credentials. Authorization is based on these credentials and occurs at the Tornjak application level.

## Deploy Keycloak Instance (Authentication Service)

We will deploy the instance of Keycloak in a dedicated namespace

```shell
# If does not exist, create a namespace to deploy Keycloak
kubectl create namespace keycloak
```

> [!IMPORTANT]
> The example uses default userid and password (`admin`,`admin`). You must change these values
> by setting `auth.adminUser` and `auth.adminPassword` as shown below.

```shell
# Deploy most recent Keycloak instance as an authentication service
helm upgrade --install -n keycloak keycloak \
--values examples/tornjak/keycloak/values.yaml \
--set auth.adminUser=your-userid --set auth.adminPassword=your-password \
oci://registry-1.docker.io/bitnamicharts/keycloak --render-subchart-notes
```

> [!IMPORTANT]
> It is important to start the Tornjak service before starting Tornjak with authentication

The example below demonstrates port forward for local access. In cloud deployment scenario,
enable Ingress to the Keycloak service accordingly.

```shell
# Start an auth Service [Keycloak] in separate terminal
kubectl -n keycloak port-forward service/keycloak 8080:80
```

See the helm Notes for more information about accessing Keycloak

## Deploy SPIRE with Tornjak User Management Enabled

Please follow the instructions for [deploying Tornjak](../README.md)
with addition of the User Management values `--values examples/tornjak/values-auth.yaml`.

> [!IMPORTANT]
> Make sure Tornjak backend User Management issuer points to the correct Keycloak issuer URL. Which is in format
> `http://<your-keycloakServicename>.<keycloak-namespace>:<your-keycloak-portnumber>/realms/tornjak`.
> For the example above it will be: `http://keycloak.keycloak:8080/realms/tornjak`
> You can set the issuer URL using `--set spire-server.tornjak.config.userManagement.issuer=http://tornjak.tornjak:8080/realms/tornjak`
>
> [!IMPORTANT]
> If audience is set, make sure the Tornjak backend `audience` is set correctly. You can set it using:
> `--set spire-server.tornjak.config.userManagement.audience=your-audience`
>
> [!TIP]
> Keep in mind, when redeploying Tornjak, you might have to recreate port forwarding for that service.

The sample [examples/tornjak/values-auth.yaml](../values-auth.yaml) assumes local
Keycloak deployment using port forwarding. When using Ingress, update the URLs accordingly.

## Access Tornjak

Follow the standard [steps for Accessing Tornjak](../README.md)
