<!-- vim: ft=markdown colorcolumn=72
-->
# Glossary

This glossary is a dictionary of terms defined as they are used by the
spire/helm-charts project.  Writing the definitions of terms here helps
to keep other documents concise and precise.  Documenting terminology
here helps prevent misundersandings, facilitating easy onboarding of new
team members.

**Deployment**
: A use of the Helm Charts to describe a single SPIRE cluster.

**Deployment Type**
: One of three supported deployments of the charts: Standalone, 
Primary, or Secondary.

**Federation**
: When one cluster is configured to trust elements of another cluster
containing a different trust domain.

**Federated Deployment**
: A Primary Deployment or Standalone Deployment that is configured
to federate with one or more Deployments.

**Primary Deployment**
: A deployment of the Helm Charts where the cluster's purpose is to
provide certificates to Secondary Deployments.

**Secondary Deployment**
: A deployment of the Helm Charts where the cluster obtains an
intermediate CA from a Primary Deployment and uses it to service
Workload Identity requests.

**Standalone Deployment**
: A deployment of the Helm Charts where the cluster both manages the CA
and services Workload Identity requests in the same cluster.

**Tiered Deployment**
: Use of the Helm Charts two or more times, such that one chart is
configured as a Primary Deployment Type and the others are configured as
Secondary Deployment Types.

**Trust Domain**
: The host field of a SPIFFE ID, naming a minimum footprint of a trust
bundle's distribution.
