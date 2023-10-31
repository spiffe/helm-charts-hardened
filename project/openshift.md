# OpenShift notes for K8S developers

## SecurityContexts

OpenShift automatically generates uid/gid's for pods. They should not be set to get this behavior.

## CSIDriver issues

A workload in a restricted namespace can not access a csidriver that isn't labeled:

```yaml
security.openshift.io/csi-ephemeral-volume-profile: restricted
```

If the CSIDriver doesn't exist, the workload is blocked from being uploaded into the cluster. This runs into ordering issues with helm install as it always loads regular workloads before CSIDriver objects.

## Pod Security Standard

Pod Security Standard (PSS) rules are automatically generated on openshift. Details at [https://docs.openshift.com/container-platform/4.13/authentication/understanding-and-managing-pod-security-admission.html](https://docs.openshift.com/container-platform/4.13/authentication/understanding-and-managing-pod-security-admission.html)

The defaults though are too chatty. It puts audit/warn still at restricted.

## Ingress

Ingress objects automatically create Role objects in the same namespace, when the ingress object is viewed as valid by openshift, if not it is ignored. A missing Role object is a sure sign that something is wrong in the Ingress.

Some things to watch out for.

When the ingress is annotated:

```yaml
  "route.openshift.io/termination": "passthrough" 
```

The ingress object can not have a path specified and the pathType needs to be ImplementationSpecific

Also, unless a secretName is specified, it can not have a tls section.

