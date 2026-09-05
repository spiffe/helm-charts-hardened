{{/*
Expand the name of the chart.
*/}}
{{- define "spire-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Spire Server deployment/statefulset
*/}}
{{- define "spire-server.kind" -}}
{{- if not (has .Values.kind (list "statefulset" "deployment")) -}}
  {{- fail "Unsupported deployment type" -}}
{{- else -}}
  {{- .Values.kind -}}
{{- end -}}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "spire-server.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Allow the release namespace to be overridden for multi-namespace deployments in combined charts
*/}}
{{- define "spire-server.namespace" -}}
  {{- if .Values.namespaceOverride -}}
    {{- .Values.namespaceOverride -}}
  {{- else if and (dig "spire" "recommendations" "enabled" false .Values.global) (dig "spire" "recommendations" "namespaceLayout" true .Values.global) }}
    {{- if ne (len (dig "spire" "namespaces" "server" "name" "" .Values.global)) 0 }}
      {{- .Values.global.spire.namespaces.server.name }}
    {{- else }}
      {{- printf "spire-server" }}
    {{- end }}
  {{- else -}}
    {{- .Release.Namespace -}}
  {{- end -}}
{{- end -}}

{{- define "spire-server.agent-namespace" -}}
  {{- if .Values.namespaceOverride -}}
    {{- .Values.namespaceOverride -}}
  {{- else if and (dig "spire" "recommendations" "enabled" false .Values.global) (dig "spire" "recommendations" "namespaceLayout" true .Values.global) }}
    {{- if ne (len (dig "spire" "namespaces" "system" "name" "" .Values.global)) 0 }}
      {{- .Values.global.spire.namespaces.system.name }}
    {{- else }}
      {{- printf "spire-system" }}
    {{- end }}
  {{- else -}}
    {{- .Release.Namespace -}}
  {{- end -}}
{{- end -}}

{{- define "spire-server.bundle-namespace-bundlepublisher" -}}
  {{- if .Values.bundlePublisher.k8sConfigMap.namespace }}
    {{- .Values.bundlePublisher.k8sConfigMap.namespace }}
  {{- else if .Values.namespaceOverride -}}
    {{- .Values.namespaceOverride -}}
  {{- else if and (dig "spire" "recommendations" "enabled" false .Values.global) (dig "spire" "recommendations" "namespaceLayout" true .Values.global) }}
    {{- if ne (len (dig "spire" "namespaces" "system" "name" "" .Values.global)) 0 }}
      {{- .Values.global.spire.namespaces.system.name }}
    {{- else }}
      {{- printf "spire-system" }}
    {{- end }}
  {{- else -}}
    {{- .Release.Namespace -}}
  {{- end -}}
{{- end -}}

{{- define "spire-server.bundle-namespace-notifier" -}}
  {{- if .Values.notifier.k8sBundle.namespace }}
    {{- .Values.notifier.k8sBundle.namespace }}
  {{- else if .Values.namespaceOverride -}}
    {{- .Values.namespaceOverride -}}
  {{- else if and (dig "spire" "recommendations" "enabled" false .Values.global) (dig "spire" "recommendations" "namespaceLayout" true .Values.global) }}
    {{- if ne (len (dig "spire" "namespaces" "system" "name" "" .Values.global)) 0 }}
      {{- .Values.global.spire.namespaces.system.name }}
    {{- else }}
      {{- printf "spire-system" }}
    {{- end }}
  {{- else -}}
    {{- .Release.Namespace -}}
  {{- end -}}
{{- end -}}

{{- define "spire-server.bundle-namespace" -}}
  {{- if .Values.notifier.k8sBundle.namespace }}
    {{- .Values.notifier.k8sBundle.namespace }}
  {{- else }}
    {{- include "spire-server.bundle-namespace-bundlepublisher" . -}}
  {{- end }}
{{- end }}

{{- define "spire-server.podMonitor.namespace" -}}
  {{- if ne (len .Values.telemetry.prometheus.podMonitor.namespace) 0 }}
    {{- .Values.telemetry.prometheus.podMonitor.namespace }}
  {{- else if ne (len (dig "telemetry" "prometheus" "podMonitor" "namespace" "" .Values.global)) 0 }}
    {{- .Values.global.telemetry.prometheus.podMonitor.namespace }}
  {{- else }}
    {{- include "spire-server.namespace" . }}
  {{- end }}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "spire-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "spire-server.labels" -}}
helm.sh/chart: {{ include "spire-server.chart" . }}
{{ include "spire-server.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "spire-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spire-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "spire-server.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "spire-server.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "spire-server.upstream-ca-secret" -}}
{{- $root := . }}
{{- with .Values.upstreamAuthority.disk -}}
{{- if eq (.secret.create | toString) "true" -}}
{{ include "spire-server.fullname" $root }}-upstream-ca
{{- else -}}
{{ default (include "spire-server.fullname" $root) .secret.name }}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "spire-server.upstream-ejbca-secret" -}}
{{- $root := . }}
{{- with .Values.upstreamAuthority.ejbca -}}
{{- if eq (.secret.create | toString) "true" -}}
{{ include "spire-server.fullname" $root }}-upstream-ejbca
{{- else -}}
{{ default (include "spire-server.fullname" $root) .secret.name }}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "spire-controller-manager.fullname" -}}
{{ include "spire-server.fullname" . | trimSuffix "-server" }}-controller-manager
{{- end }}

{{- define "spire-controller-manager.standalone-fullname" -}}
{{ include "spire-controller-manager.fullname" . }}-standalone
{{- end }}

{{- define "spire-controller-manager.standalone-serviceAccountName" -}}
{{ include "spire-controller-manager.standalone-fullname" . }}
{{- end }}

{{- define "spire-controller-manager.standalone-selectorLabels" -}}
app.kubernetes.io/name: {{ include "spire-controller-manager.standalone-fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "spire-controller-manager.standalone-labels" -}}
helm.sh/chart: {{ include "spire-server.chart" . }}
{{ include "spire-controller-manager.standalone-selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Name of the dedicated k8s_psat cluster profile (configmap.yaml) used to
attest the standalone controller manager's own in-pod spire-agent
sidecar, scoped via service_account_allow_list to just that Deployment's
ServiceAccount, with use_pod_uid_for_agent_id enabled.
*/}}
{{- define "spire-controller-manager.standalone-attestor-cluster-name" -}}
{{- printf "%s-cm-standalone" (include "spire-lib.cluster-name" .) }}
{{- end }}

{{/* Path, inside the standalone Deployment's Pod, of the in-pod spire-agent's own Workload API socket. Shared between its two containers via an emptyDir. */}}
{{- define "spire-controller-manager.standalone-agent-socket-path" -}}
/tmp/spire-agent/public/api.sock
{{- end }}

{{/*
SPIFFE ID of the "node alias" that grants the standalone Deployment's own
in-pod spire-agent an additional identity, matched purely by node-attestor-
style selectors (parentID = spiffe://<td>/spire/server), regardless of the
concrete (unpredictable ahead of time) pod-UID-based agent ID it attests
with. See controller-manager-standalone.yaml for the static registration
entry that establishes this.
*/}}
{{- define "spire-controller-manager.standalone-alias-id" -}}
spiffe://{{ include "spire-lib.trust-domain" . }}/agent-alias/controller-manager-standalone
{{- end }}

{{/* SPIFFE ID of the standalone Deployment's own controller-manager workload, parented to the alias above. */}}
{{- define "spire-controller-manager.standalone-workload-id" -}}
spiffe://{{ include "spire-lib.trust-domain" . }}/ns/{{ include "spire-server.namespace" . }}/sa/{{ include "spire-controller-manager.standalone-serviceAccountName" . }}
{{- end }}

{{/*
Absolute path of the spire-controller-manager binary inside its own
container image, used as a unix:path WorkloadAttestor selector to
identify that co-located container regardless of which UID it runs as
(so this works unchanged under OpenShift's per-namespace random UID
assignment, unlike a unix:uid selector).
*/}}
{{- define "spire-controller-manager.standalone-workload-path" -}}
/spire-controller-manager
{{- end }}

{{/*
The dictionary of external clusters a standalone controller manager
should reconcile - one controller manager Deployment per entry, each
with its own in-pod spire-agent sidecar and its own SPIFFE identity, in
addition to (not instead of) the single default Deployment above. Same
fallback convention as spire-controller-manager.containers: explicit
externalControllerManagers.clusters overrides win, else every cluster
in kubeConfigs is used.
*/}}
{{- define "spire-controller-manager.standalone-clusters" -}}
{{- default .Values.kubeConfigs .Values.externalControllerManagers.clusters | toYaml }}
{{- end }}

{{/*
Per-external-cluster variants of the standalone-* helpers above, one
Deployment per cluster name. Takes a dict: root (the root context),
name (the cluster name key from spire-controller-manager.standalone-
clusters).
*/}}
{{- define "spire-controller-manager.standalone-cluster-fullname" -}}
{{- printf "%s-%s" (include "spire-controller-manager.standalone-fullname" .root) .name }}
{{- end }}

{{- define "spire-controller-manager.standalone-cluster-serviceAccountName" -}}
{{ include "spire-controller-manager.standalone-cluster-fullname" . }}
{{- end }}

{{- define "spire-controller-manager.standalone-cluster-selectorLabels" -}}
app.kubernetes.io/name: {{ include "spire-controller-manager.standalone-cluster-fullname" . }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end }}

{{- define "spire-controller-manager.standalone-cluster-labels" -}}
helm.sh/chart: {{ include "spire-server.chart" .root }}
{{ include "spire-controller-manager.standalone-cluster-selectorLabels" . }}
{{- if .root.Chart.AppVersion }}
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
{{- end }}

{{- define "spire-controller-manager.standalone-cluster-attestor-cluster-name" -}}
{{- printf "%s-%s" (include "spire-controller-manager.standalone-attestor-cluster-name" .root) .name }}
{{- end }}

{{- define "spire-controller-manager.standalone-cluster-alias-id" -}}
spiffe://{{ include "spire-lib.trust-domain" .root }}/agent-alias/controller-manager-standalone-{{ .name }}
{{- end }}

{{- define "spire-controller-manager.standalone-cluster-workload-id" -}}
spiffe://{{ include "spire-lib.trust-domain" .root }}/ns/{{ include "spire-server.namespace" .root }}/sa/{{ include "spire-controller-manager.standalone-cluster-serviceAccountName" . }}
{{- end }}

{{/*
Dispatcher helpers used by controller-manager-standalone.yaml to render
one Deployment (with its own in-pod agent, bootstrap identity, etc) per
dict "root" "name" (root context, cluster name key). name "" means the
single default/local instance (using the standalone-* helpers above);
any other value means one of the additional per-external-cluster
instances (using the standalone-cluster-* helpers above), letting the
same template body handle both without duplicating it.
*/}}
{{- define "spire-controller-manager.standalone-instance-fullname" -}}
{{- if eq .name "" -}}
{{- include "spire-controller-manager.standalone-fullname" .root -}}
{{- else -}}
{{- include "spire-controller-manager.standalone-cluster-fullname" . -}}
{{- end -}}
{{- end }}

{{- define "spire-controller-manager.standalone-instance-serviceAccountName" -}}
{{- if eq .name "" -}}
{{- include "spire-controller-manager.standalone-serviceAccountName" .root -}}
{{- else -}}
{{- include "spire-controller-manager.standalone-cluster-serviceAccountName" . -}}
{{- end -}}
{{- end }}

{{- define "spire-controller-manager.standalone-instance-selectorLabels" -}}
{{- if eq .name "" -}}
{{- include "spire-controller-manager.standalone-selectorLabels" .root -}}
{{- else -}}
{{- include "spire-controller-manager.standalone-cluster-selectorLabels" . -}}
{{- end -}}
{{- end }}

{{- define "spire-controller-manager.standalone-instance-labels" -}}
{{- if eq .name "" -}}
{{- include "spire-controller-manager.standalone-labels" .root -}}
{{- else -}}
{{- include "spire-controller-manager.standalone-cluster-labels" . -}}
{{- end -}}
{{- end }}

{{- define "spire-controller-manager.standalone-instance-attestor-cluster-name" -}}
{{- if eq .name "" -}}
{{- include "spire-controller-manager.standalone-attestor-cluster-name" .root -}}
{{- else -}}
{{- include "spire-controller-manager.standalone-cluster-attestor-cluster-name" . -}}
{{- end -}}
{{- end }}

{{- define "spire-controller-manager.standalone-instance-alias-id" -}}
{{- if eq .name "" -}}
{{- include "spire-controller-manager.standalone-alias-id" .root -}}
{{- else -}}
{{- include "spire-controller-manager.standalone-cluster-alias-id" . -}}
{{- end -}}
{{- end }}

{{- define "spire-controller-manager.standalone-instance-workload-id" -}}
{{- if eq .name "" -}}
{{- include "spire-controller-manager.standalone-workload-id" .root -}}
{{- else -}}
{{- include "spire-controller-manager.standalone-cluster-workload-id" . -}}
{{- end -}}
{{- end }}

{{/*
"true" if this standalone instance consumes a kubeConfigs entry that
uses jwtSVIDExec (i.e. the default/local instance never does, per-
external-cluster instances do if their resolved kubeConfigName's entry
sets jwtSVIDExec). Drives both the extra bootstrap workload entry
in controller-manager-standalone.yaml and the plugin-staging init
containers on the same Pod.
*/}}
{{- define "spire-controller-manager.standalone-instance-jwt-exec-needed" -}}
{{- $root := .root -}}
{{- $result := "false" -}}
{{- if ne .name "" -}}
{{-   $clusterSettings := dict -}}
{{-   if hasKey $root.Values.externalControllerManagers.clusters .name -}}
{{-     $clusterSettings = index $root.Values.externalControllerManagers.clusters .name -}}
{{-   end -}}
{{-   $kubeConfigName := default .name (default "" $clusterSettings.kubeConfigName) -}}
{{-   $kubeConfigEntry := default dict (index $root.Values.kubeConfigs $kubeConfigName) -}}
{{-   if hasKey $kubeConfigEntry "jwtSVIDExec" -}}
{{-     $result = "true" -}}
{{-   end -}}
{{- end -}}
{{- $result -}}
{{- end }}

{{/* controller-manager-config{suffix}.yaml suffix for this instance: "" for the default/local instance, "-<name>" for a per-external-cluster instance (matches controller-manager-configmap.yaml's own suffixing). */}}
{{- define "spire-controller-manager.standalone-instance-config-suffix" -}}
{{- if ne .name "" -}}
{{- printf "-%s" .name -}}
{{- end -}}
{{- end }}

{{/*
Pod security context for the standalone controller manager Deployment.
Mirrors spire-lib.podsecuritycontext, but - like
spire-identity-exchange.podSecurityContext - leaves runAsUser/runAsGroup
unset on OpenShift so its SCC can assign the namespace's random UID,
since (unlike the fixed-UID pattern this chart used to rely on) the
unix:path selector above doesn't need a known-ahead-of-time UID at all.
*/}}
{{- define "spire-controller-manager.standalone-podSecurityContext" -}}
{{-   $podSecurityContext := deepCopy .Values.controllerManager.standalone.podSecurityContext }}
{{-   $openshift := ((.Values).global).openshift | default false }}
{{-   if not $openshift }}
{{-     if not (hasKey $podSecurityContext "runAsUser") }}
{{-       $_ := set $podSecurityContext "runAsUser" 1000 }}
{{-     end }}
{{-     if not (hasKey $podSecurityContext "runAsGroup") }}
{{-       $_ := set $podSecurityContext "runAsGroup" 1000 }}
{{-     end }}
{{-   end }}
{{-   toYaml $podSecurityContext }}
{{- end }}

{{/*
The host:port of the spire-server Service, used by the standalone
controller manager Deployment to dial the SPIRE Server API over TCP. Falls
back to the Service's own name/namespace/port when
controllerManager.standalone.spireServerAddress is unset.
*/}}
{{- define "spire-controller-manager.standalone-spire-server-address" -}}
{{- if .Values.controllerManager.standalone.spireServerAddress }}
{{-   .Values.controllerManager.standalone.spireServerAddress }}
{{- else }}
{{-   printf "%s.%s.svc:%v" (include "spire-server.fullname" .) (include "spire-server.namespace" .) .Values.service.port }}
{{- end -}}
{{- end }}

{{/*
Name of the chart-generated Secret holding the inline kubeConfigs entries.
*/}}
{{- define "spire-server.kubeconfigs-secret-name" -}}
{{ include "spire-server.fullname" . }}-kubeconfigs
{{- end }}

{{/*
Path of the staged jwt-svid exec plugin binary inside the shared plugins volume. Used both as the
init-container copy target and as the exec kubeconfig command, so the two must stay in sync.
*/}}
{{- define "spire-server.jwt-svid-exec-binary-path" -}}
/plugins/jwt-svid-exec
{{- end }}

{{/*
Init containers that stage the jwt-svid-exec plugin binary into a shared
"plugins" emptyDir. Rendered into both the spire-server Pod (see
server-resource.yaml) and each standalone controller-manager Pod (see
controller-manager-standalone.yaml). The consumer container mounts the
same "plugins" volume read-only at /plugins and execs the plugin from
the path returned by spire-server.jwt-svid-exec-binary-path.

The spire-server image itself ships no shell, so a busybox is first
staged into the shared volume (init-plugins) and then used to copy the
plugin binary (init-jwt-svid-exec), and finally the busybox is removed
(finalize-plugins).
*/}}
{{- define "spire-server.jwt-svid-exec-init-containers" -}}
- name: init-plugins
  securityContext:
    {{- include "spire-lib.securitycontext" . | nindent 4 }}
  image: {{ template "spire-lib.image" (dict "appVersion" .Chart.AppVersion "image" .Values.tools.busybox.image "global" .Values.global) }}
  command:
    - busybox
    - sh
    - -ec
    - |
      cp -a /bin/busybox /plugins/busybox
  volumeMounts:
    - name: plugins
      mountPath: /plugins
  imagePullPolicy: {{ .Values.tools.busybox.image.pullPolicy }}
- name: init-jwt-svid-exec
  securityContext:
    {{- include "spire-lib.securitycontext" . | nindent 4 }}
  image: {{ template "spire-lib.image" (dict "appVersion" .Chart.AppVersion "image" .Values.jwtSVIDExecConfig.image "global" .Values.global) }}
  command:
    - /plugins/busybox
    - sh
    - -ec
    - |
      /plugins/busybox cp -a {{ .Values.jwtSVIDExecConfig.pluginPath }} {{ include "spire-server.jwt-svid-exec-binary-path" . }}
  volumeMounts:
    - name: plugins
      mountPath: /plugins
  imagePullPolicy: {{ .Values.jwtSVIDExecConfig.image.pullPolicy }}
- name: finalize-jwt-svid-exec
  securityContext:
    {{- include "spire-lib.securitycontext" . | nindent 4 }}
  image: {{ template "spire-lib.image" (dict "appVersion" .Chart.AppVersion "image" .Values.tools.busybox.image "global" .Values.global) }}
  command:
    - busybox
    - sh
    - -ec
    - |
      rm -f /plugins/busybox
  volumeMounts:
    - name: plugins
      mountPath: /plugins
  imagePullPolicy: {{ .Values.tools.busybox.image.pullPolicy }}
{{- end }}

{{/*
Resolves jwtSVIDExecConfig.spiffeID to a full spiffe:// URI, validating
the trust domain. Used by both the kubeconfig template (server-admin-api
source in sidecar mode) and the extra standalone bootstrap workload
entry that materializes this identity for workload-api source in
standalone mode.
*/}}
{{- define "spire-server.jwt-svid-exec-spiffeID" -}}
{{- $root := . -}}
{{- $spiffeID := $root.Values.jwtSVIDExecConfig.spiffeID -}}
{{- if not $spiffeID -}}
{{- fail "jwtSVIDExecConfig.spiffeID is required when a kubeConfigs entry uses jwtSVIDExec" -}}
{{- end -}}
{{- $chartTD := include "spire-lib.trust-domain" $root -}}
{{- if hasPrefix "/" $spiffeID -}}
{{- printf "spiffe://%s%s" $chartTD $spiffeID -}}
{{- else if hasPrefix "spiffe://" $spiffeID -}}
{{- $idTD := $spiffeID | trimPrefix "spiffe://" | splitList "/" | first -}}
{{- if ne $idTD $chartTD -}}
{{- fail (printf "jwtSVIDExecConfig.spiffeID trust domain %q must match the chart trust domain %q" $idTD $chartTD) -}}
{{- end -}}
{{- $spiffeID -}}
{{- else -}}
{{- fail (printf "jwtSVIDExecConfig.spiffeID %q must be a spiffe:// URI or a path starting with \"/\"" $spiffeID) -}}
{{- end -}}
{{- end }}

{{/*
Deterministic hint applied to the extra standalone bootstrap workload
entry (see controller-manager-standalone.yaml) and referenced from the
kubeconfig via SPIFFE_JWT_HINT, so the exec plugin selects that specific
JWT-SVID out of any others the Workload API might return for the
standalone controller-manager Pod.
*/}}
{{- define "spire-server.jwt-svid-exec-hint" -}}
jwt-svid-exec
{{- end }}

{{- define "spire-server.jwt-svid-exec-kubeconfig" -}}
{{- $jwtSVIDExec := .jwtSVIDExec -}}
{{- $root := .root -}}
{{- $mode := default "sidecar" .mode -}}
{{- $spiffeID := include "spire-server.jwt-svid-exec-spiffeID" $root -}}
apiVersion: v1
kind: Config
clusters:
- name: cluster
  cluster:
    server: {{ $jwtSVIDExec.server | quote }}
    certificate-authority-data: {{ $jwtSVIDExec.certificateAuthorityData | quote }}
users:
- name: spiffe
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1
      command: {{ include "spire-server.jwt-svid-exec-binary-path" $root }}
      interactiveMode: Never
      env:
      {{- if eq $mode "standalone" }}
      - name: SPIFFE_JWT_SOURCE
        value: "workload-api"
      - name: SPIFFE_ENDPOINT_SOCKET
        value: {{ printf "unix://%s" (include "spire-controller-manager.standalone-agent-socket-path" $root) | quote }}
      - name: SPIFFE_JWT_HINT
        value: {{ include "spire-server.jwt-svid-exec-hint" . | quote }}
      {{- else }}
      - name: SPIFFE_JWT_SOURCE
        value: "server-admin-api"
      - name: SPIRE_SERVER_SOCKET
        value: "unix:///tmp/spire-server/private/api.sock"
      - name: SPIFFE_ID
        value: {{ $spiffeID | quote }}
      {{- end }}
      - name: SPIFFE_JWT_AUDIENCE
        value: {{ $jwtSVIDExec.audience | default "k8s" | quote }}
contexts:
- name: cluster
  context:
    cluster: cluster
    user: spiffe
current-context: cluster
{{- end }}

{{- define "spire-server.serviceAccountAllowedList" }}
{{- $releaseNamespace := include "spire-server.agent-namespace" . }}
{{- if ne (len .Values.nodeAttestor.k8sPSAT.serviceAccountAllowList) 0 }}
{{-   $list := list }}
{{-   range .Values.nodeAttestor.k8sPSAT.serviceAccountAllowList }}
{{-     if contains ":" . }}
{{-       $list = append $list . }}
{{-     else }}
{{-       $list = append $list ( printf "%s:%s" $releaseNamespace . ) | }}
{{-     end }}
{{-   end }}
{{-   $list | toJson }}
{{- else }}
[{{ printf "%s:%s-agent" $releaseNamespace .Release.Name | quote }}]
{{- end }}
{{- end }}

{{- define "spire-server.config-sqlite-query" }}
{{- $lst := list }}
{{- range . }}
{{- range $key, $value := . }}
{{- $eValue := toString $value }}
{{- $entry := printf "%s=%s" (urlquery $key) (urlquery $eValue) }}
{{- $lst = append $lst $entry }}
{{- end }}
{{- end }}
{{- if gt (len $lst) 0 }}
{{- printf "?%s" (join "&" (uniq $lst)) }}
{{- end }}
{{- end }}

{{- define "spire-server.config-mysql-query" }}
{{- $lst := list }}
{{- range . }}
{{- range $key, $value := . }}
{{- $eValue := toString $value }}
{{- $entry := printf "%s=%s" (urlquery $key) (urlquery $eValue) }}
{{- $lst = append $lst $entry }}
{{- end }}
{{- end }}
{{- $lst = append $lst "parseTime=true" }}
{{- printf "?%s" (join "&" (uniq $lst)) }}
{{- end }}

{{- define "spire-server.config-postgresql-options" }}
{{- $lst := list }}
{{- range . }}
{{- range $key, $value := . }}
{{- $eValue := toString $value }}
{{- $entry := printf "%s=%s" $key $eValue }}
{{- $lst = append $lst $entry }}
{{- end }}
{{- end }}
{{- if gt (len $lst) 0 }}
{{- printf " %s" (join " " $lst) }}
{{- end }}
{{- end }}

{{- define "spire-server.datastore-is-postgres" -}}
{{- or (eq .Values.dataStore.sql.databaseType "postgres") (eq .Values.dataStore.sql.databaseType "aws_postgres") -}}
{{- end }}

{{- define "spire-server.datastore-postgres-passwordless" -}}
{{- $isPostgres := eq (include "spire-server.datastore-is-postgres" .) "true" -}}
{{- and $isPostgres (eq .Values.dataStore.sql.password "") (not .Values.dataStore.sql.externalSecret.enabled) -}}
{{- end }}

{{- define "spire-server.datastore-postgres-ro-passwordless" -}}
{{- $isPostgres := eq (include "spire-server.datastore-is-postgres" .) "true" -}}
{{- and $isPostgres (eq .Values.dataStore.sql.readOnly.password "") (not .Values.dataStore.sql.readOnly.externalSecret.enabled) -}}
{{- end }}

{{- define "spire-server.datastore-config" }}
{{- $config := dict }}
{{- $pw := "" }}
{{- $ropw := "" }}
{{- if eq .Values.dataStore.sql.databaseType "sqlite3" }}
  {{- $_ := set $config "database_type" "sqlite3" }}
  {{- if .Values.dataStore.sql.inMemory }}
  {{- /* cache=shared is not optional: without it every pooled connection opens its own
         empty database, so the server silently loses every write it did not make itself. */}}
  {{- $query := include "spire-server.config-sqlite-query" (concat (list (dict "mode" "memory") (dict "cache" "shared")) .Values.dataStore.sql.options) }}
  {{- $_ := set $config "connection_string" (printf "memdb%s" $query) }}
  {{- else }}
  {{- $query := include "spire-server.config-sqlite-query" .Values.dataStore.sql.options }}
  {{- $_ := set $config "connection_string" (printf "%s%s" .Values.dataStore.sql.file $query) }}
  {{- end }}
{{- else if or (eq .Values.dataStore.sql.databaseType "mysql") (eq .Values.dataStore.sql.databaseType "aws_mysql") (eq .Values.dataStore.sql.databaseType "gcp_mysql_sa_iam") }}
  {{- if eq .Values.dataStore.sql.databaseType "mysql" }}
  {{-   $_ := set $config "database_type" "mysql" }}
  {{-   $pw = "${DBPW}" }}
  {{-   $ropw = "${RODBPW}" }}
  {{- else if eq .Values.dataStore.sql.databaseType "gcp_mysql_sa_iam" }}
  {{-   $_ := set $config "database_type" "mysql" }}
  {{-   $pw = "" }}
  {{-   $ropw = "" }}
  {{- else }}
  {{-   $_ := set $config "database_type" (list (dict "aws_mysql" (dict "region" .Values.dataStore.sql.region))) }}
  {{-   $pw = "${DBPW}" }}
  {{-   $ropw = "${RODBPW}" }}
  {{-   end }}
  {{- $port := int .Values.dataStore.sql.port | default 3306 }}
  {{- $query := include "spire-server.config-mysql-query" .Values.dataStore.sql.options }}
  {{- if eq $pw "" }}
  {{-   $_ := set $config "connection_string" (printf "%s@tcp(%s:%d)/%s%s" .Values.dataStore.sql.username .Values.dataStore.sql.host $port .Values.dataStore.sql.databaseName $query) }}
  {{- else }}
  {{-   $_ := set $config "connection_string" (printf "%s:%s@tcp(%s:%d)/%s%s" .Values.dataStore.sql.username $pw .Values.dataStore.sql.host $port .Values.dataStore.sql.databaseName $query) }}
  {{- end }}
  {{- if .Values.dataStore.sql.readOnly.enabled }}
  {{-   $roPort := int .Values.dataStore.sql.readOnly.port | default 3306 }}
  {{-   $roQuery := include "spire-server.config-mysql-query" .Values.dataStore.sql.readOnly.options }}
  {{-   if eq $ropw "" }}
  {{-     $_ := set $config "ro_connection_string" (printf "%s@tcp(%s:%d)/%s%s" .Values.dataStore.sql.readOnly.username .Values.dataStore.sql.readOnly.host $roPort .Values.dataStore.sql.readOnly.databaseName $roQuery) }}
  {{-   else }}
  {{-     $_ := set $config "ro_connection_string" (printf "%s:%s@tcp(%s:%d)/%s%s" .Values.dataStore.sql.readOnly.username $ropw .Values.dataStore.sql.readOnly.host $roPort .Values.dataStore.sql.readOnly.databaseName $roQuery) }}
  {{-   end }}
  {{- end }}
{{- else if or (eq .Values.dataStore.sql.databaseType "postgres") (eq .Values.dataStore.sql.databaseType "aws_postgres") }}
  {{- if eq .Values.dataStore.sql.databaseType "postgres" }}
  {{-   $_ := set $config "database_type" "postgres" }}
  {{- else }}
  {{-   $_ := set $config "database_type" (list (dict "aws_postgres" (dict "region" .Values.dataStore.sql.region))) }}
  {{- end }}
  {{- if ne (include "spire-server.datastore-postgres-passwordless" .) "true" }}
  {{-   $pw = " password=${DBPW}" }}
  {{- end }}
  {{- if ne (include "spire-server.datastore-postgres-ro-passwordless" .) "true" }}
  {{-   $ropw = " password=${RODBPW}" }}
  {{- end }}
  {{- $sslPaths := "" }}
  {{- if ne .Values.dataStore.sql.rootCAPath "" }}
  {{-   $sslPaths = printf "%s sslrootcert=%s" $sslPaths .Values.dataStore.sql.rootCAPath }}
  {{- end }}
  {{- if ne .Values.dataStore.sql.clientCertPath "" }}
  {{-   $sslPaths = printf "%s sslcert=%s" $sslPaths .Values.dataStore.sql.clientCertPath }}
  {{- end }}
  {{- if ne .Values.dataStore.sql.clientKeyPath "" }}
  {{-   $sslPaths = printf "%s sslkey=%s" $sslPaths .Values.dataStore.sql.clientKeyPath }}
  {{- end }}
  {{- $port := int .Values.dataStore.sql.port | default 5432 }}
  {{- $options:= include "spire-server.config-postgresql-options" .Values.dataStore.sql.options }}
  {{- $_ := set $config "connection_string" (printf "dbname=%s user=%s%s host=%s port=%d%s%s" .Values.dataStore.sql.databaseName .Values.dataStore.sql.username $pw .Values.dataStore.sql.host $port $options $sslPaths) }}
  {{- if .Values.dataStore.sql.readOnly.enabled }}
  {{-   $roPort := int .Values.dataStore.sql.readOnly.port | default 5432 }}
  {{-   $roOptions:= include "spire-server.config-postgresql-options" .Values.dataStore.sql.readOnly.options }}
  {{-   $_ := set $config "ro_connection_string" (printf "dbname=%s user=%s%s host=%s port=%d%s%s" .Values.dataStore.sql.readOnly.databaseName .Values.dataStore.sql.readOnly.username $ropw .Values.dataStore.sql.readOnly.host $roPort $roOptions $sslPaths) }}
  {{- end }}
{{- else }}
  {{- fail "Unsupported database type" }}
{{- end }}
{{- $config | toYaml }}
{{- end }}

{{- define "spire-server.upstream-spire-address" }}
{{- if ne (len (dig "spire" "upstreamSpireAddress" "" .Values.global)) 0 }}
{{- print .Values.global.spire.upstreamSpireAddress }}
{{- else if .Values.upstreamAuthority.spire.server.address }}
{{-   if contains "." .Values.upstreamAuthority.spire.server.address }}
{{-     print .Values.upstreamAuthority.spire.server.address }}
{{-   else }}
{{-     printf "%s.%s" .Values.upstreamAuthority.spire.server.address (include "spire-lib.trust-domain" .) }}
{{-   end }}
{{- else if .Values.upstreamAuthority.spire.server.nameOverride }}
{{- printf "%s-%s" .Release.Name .Values.upstreamAuthority.spire.server.nameOverride }}
{{- else }}
{{- print .Values.upstreamAuthority.spire.server.address }}
{{- end }}
{{- end }}

{{/*
Tornjak specific section
*/}}

{{- define "spire-tornjak.fullname" -}}
{{ include "spire-server.fullname" . | trimSuffix "-server" }}-tornjak
{{- end }}

{{- define "spire-tornjak.config" -}}
{{ include "spire-tornjak.fullname" . }}-config
{{- end }}

{{- define "spire-tornjak.backend" -}}
{{ include "spire-tornjak.fullname" . }}-backend
{{- end }}

{{/*
Tornjak automatically determines the connection type based on provided configuration.
When TLS Secret is provided, it enables TLS connection.
When TLS Secret and User CA Secret (or ConfigMap) are provided, it enables mTLS connection.
Otherwise it starts HTTP Connection
The code below determines what connection type should be used.
*/}}
{{- define "spire-tornjak.connectionType" -}}

{{- if (lookup "v1" "Secret" (include "spire-server.namespace" .) .Values.tornjak.config.tlsSecret) -}}

{{- $caType := default "INVALID" .Values.tornjak.config.clientCA.type }}
{{- if (lookup "v1" $caType (include "spire-server.namespace" .) .Values.tornjak.config.clientCA.name) -}}
{{- printf "mtls" -}}
{{- else }}
{{- printf "tls" -}}
{{- end -}}
{{- else -}}
{{- printf "http" -}}
{{- end -}}
{{- end -}}

{{- define "spire-tornjak.servicename" -}}
{{- include "spire-tornjak.backend" . -}}
{{- end -}}

{{- define "spire-server.test.federation-ingress-args" }}
{{-   $args := list }}
{{-   $host := "" }}
{{-   if .host }}
{{-     $host = .host }}
{{-   else }}
{{-     $host = include "spire-lib.ingress-calculated-name" (dict "Values" .Values "ingress" .Values.federation.ingress) }}
{{-     if gt (len .Values.federation.ingress.tls) 0 }}
{{-       $host = index (index (index .Values.federation.ingress.tls 0) "hosts") 0 }}
{{-     end }}
{{-   end }}
{{-   if dig "tests" "tls" "enabled" false .Values }}
{{-     if ne (len (dig "tests" "tls" "customCA" "" .Values)) 0 }}
{{-       $args = append $args "--cacert" }}
{{-       $args = append $args "/ca/ca.crt" }}
{{-     end }}
{{-     $args = append $args (printf "https://%s/" $host) }}
{{-   else }}
{{-     $args = append $args (printf "-k -L http://%s/" $host) }}
{{-   end }}
{{ $args | toYaml }}
{{- end -}}

{{- define "spire-server.controller-manager-class-name" -}}
{{-   if and (hasKey . "settings") (hasKey .settings "className") }}
{{-       .settings.className }}
{{-   else if and (hasKey . "defaults") .defaults.className }}
{{-       .defaults.className }}
{{-   else if .Values.controllerManager.className }}
{{-       .Values.controllerManager.className }}
{{-   else }}
{{-     .Release.Namespace }}-{{ default .Release.Name .Values.crNameOverride }}
{{-   end -}}
{{- end -}}

{{- define "spire-server.ca-subject-country" }}
{{-   $g := dig "spire" "caSubject" "country" "" .Values.global }}
{{-   default .Values.caSubject.country $g }}
{{- end }}

{{- define "spire-server.ca-subject-organization" }}
{{-   $g := dig "spire" "caSubject" "organization" "" .Values.global }}
{{-   default .Values.caSubject.organization $g }}
{{- end }}

{{- define "spire-server.ca-subject-common-name" }}
{{-   $g := dig "spire" "caSubject" "commonName" "" .Values.global }}
{{-   default .Values.caSubject.commonName $g }}
{{- end }}

{{- define "spire-server.external-server-subject-kind" -}}
{{-   $kind := .Values.externalServerSubject.kind | default "User" }}
{{-   if not (has $kind (list "User" "Group" "ServiceAccount")) }}
{{-     fail (printf "Unknown externalServerSubject.kind: %s (must be \"User\", \"Group\", or \"ServiceAccount\")" $kind) }}
{{-   end }}
{{-   $kind }}
{{- end }}

{{- define "spire-server.subject" }}
subjects:
{{-   if .Values.externalServer }}
{{-     $kind := include "spire-server.external-server-subject-kind" . }}
{{-     if eq $kind "ServiceAccount" }}
- kind: ServiceAccount
  name: {{ .Values.externalServerSubject.name | quote }}
  namespace: {{ .Values.externalServerSubject.namespace | default (include "spire-server.namespace" .) | quote }}
{{-     else }}
- apiGroup: rbac.authorization.k8s.io
  kind: {{ $kind }}
  name: {{ .Values.externalServerSubject.name | quote }}
{{-     end }}
{{-   else }}
- kind: ServiceAccount
  name: {{ include "spire-server.serviceAccountName" . }}
  namespace: {{ include "spire-server.namespace" . }}
{{-   end }}
{{- end }}

{{- define "spire-server.podSecurityContext" -}}
{{-   $podSecurityContext := include "spire-lib.podsecuritycontext" . | fromYaml }}
{{-   $openshift := ((.Values).global).openshift | default false }}
{{-   if not $openshift }}
{{-     if not (hasKey $podSecurityContext "runAsUser") }}
{{-       $_ := set $podSecurityContext "runAsUser" 1000 }}
{{-     end }}
{{-     if not (hasKey $podSecurityContext "runAsGroup") }}
{{-       $_ := set $podSecurityContext "runAsGroup" 1000 }}
{{-     end }}
{{-   end }}
{{-   toYaml $podSecurityContext }}
{{- end }}

{{- define "spire-server.identity-exchange-spiffe-prefix" -}}
{{-   $cn := "" }}
{{-   if .Values.nodeAttestor.x509POP.addClusterName.spiffePrefix }}
{{-     $cn = printf "/%s" (include "spire-lib.cluster-name" .) }}
{{-   end }}
{{-   replace "${HELM_ADD_CLUSTER_NAME}" $cn .Values.nodeAttestor.x509POP.spiffePrefix }}
{{- end }}
