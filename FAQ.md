# Frequently Asked Questions

- [Pods are stuck terminating after uninstall. How do I fix it?](#pods-are-stuck-terminating-after-uninstall-how-do-i-fix-it)
- [Uninstall is stuck. How do I fix it?](#uninstall-is-stuck-how-do-i-fix-it)
- [The PSAT plugin is not working](#the-psat-plugin-is-not-working)

## Pods are stuck terminating after uninstall. How do I fix it?

If you uninstall the SPIRE chart before all users of the CSI driver are removed, Pods will get stuck in a terminating state waiting for the driver, that no longer is installed, to unmount the volumes for the Pod. In order to fix this, reinstall the chart and remove all affected workloads that are not part of the SPIRE helm chart itself, before attempting to remove SPIRE again.

You can discover Pods that use the driver with the following command:
```
kubectl get pods --all-namespaces -o go-template='{{range .items}}{{$nn := printf "%s %s" .metadata.namespace .metadata.name}}{{range .spec.volumes}}{{if .csi.driver}}{{if eq .csi.driver "csi.spiffe.io"}}{{printf "%s\n" $nn}}{{end}}{{end}}{{end}}{{end}}'
```

## Uninstall is stuck. How do I fix it?

If you uninstall the SPIFFE CSI driver manually before removing the chart, Pods can still be using the driver and are unable to unmount the CSI volume.

To resolve, reinstall the chart before trying to remove it again. 

## The PSAT plugin is not working

The chart requires `Projected Service Account Tokens` which has to be enabled on your Kubernetes API server. In most cases this is already done for you.

> **Note**: This is enabled by default with newer versions as shown by the existence of:
>
>        - --service-account-issuer
>        - --service-account-key-file
>        - --service-account-signing-key-file

See [Service Account Token Volume Projection](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#serviceaccount-token-volume-projection) in the Kubernetes docs for more details.

To enable Projected Service Account Tokens on Docker for Mac/Windows run the following
command to SSH into the Docker Desktop K8s VM.

```bash
docker run -it --privileged --pid=host debian nsenter -t 1 -m -u -n -i sh
```
Then add the following to `/etc/kubernetes/manifests/kube-apiserver.yaml`
```yaml
spec:
  containers:
    - command:
        - kube-apiserver
        - --api-audiences=api,spire-server
        - --service-account-issuer=api,spire-agent
        - --service-account-key-file=/run/config/pki/sa.pub
        - --service-account-signing-key-file=/run/config/pki/sa.key
```
