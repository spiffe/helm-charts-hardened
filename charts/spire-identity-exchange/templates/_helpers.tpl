{{/*
Expand the name of the chart.
*/}}
{{- define "spire-identity-exchange.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "spire-identity-exchange.fullname" -}}
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
{{- define "spire-identity-exchange.namespace" -}}
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

{{- define "spire-identity-exchange.podMonitor.namespace" -}}
  {{- if ne (len .Values.telemetry.prometheus.podMonitor.namespace) 0 }}
    {{- .Values.telemetry.prometheus.podMonitor.namespace }}
  {{- else if ne (len (dig "telemetry" "prometheus" "podMonitor" "namespace" "" .Values.global)) 0 }}
    {{- .Values.global.telemetry.prometheus.podMonitor.namespace }}
  {{- else }}
    {{- include "spire-identity-exchange.namespace" . }}
  {{- end }}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "spire-identity-exchange.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "spire-identity-exchange.labels" -}}
helm.sh/chart: {{ include "spire-identity-exchange.chart" . }}
{{ include "spire-identity-exchange.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "spire-identity-exchange.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spire-identity-exchange.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "spire-identity-exchange.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "spire-identity-exchange.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "spire-identity-exchange.workload-api-socket-path" -}}
{{- printf "/spiffe-workload-api/%s" .Values.agentSocketName }}
{{- end }}

{{/*
Volume name for an extra SPIFFE CSI driver. Driver names are DNS subdomains and may
contain dots, which a volume name (a DNS-1123 label) may not, so squash every run of
non-alphanumeric characters down to a single dash.
Args: the driver name as a string
*/}}
{{- define "spire-identity-exchange.csi-volume-name" -}}
{{- printf "spiffe-workload-api-%s" (trimAll "-" (regexReplaceAll "[^a-z0-9]+" (lower .) "-")) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Path to the SPIRE Agent workload socket one auth plugin should talk to. A plugin that
names no driver of its own, or names the one the exchange itself uses, gets the socket
already mounted for the pod; anything else gets its own mount under /spiffe-workload-apis.
Args: dict "root" <root context> "driver" <csi driver name, may be empty>
*/}}
{{- define "spire-identity-exchange.plugin-workload-api-socket-path" -}}
{{-   $root := .root }}
{{-   $driver := .driver | default "" }}
{{-   if or (eq $driver "") (eq $driver $root.Values.csiDriverName) }}
{{-     include "spire-identity-exchange.workload-api-socket-path" $root }}
{{-   else }}
{{-     printf "/spiffe-workload-apis/%s/%s" $driver $root.Values.agentSocketName }}
{{-   end }}
{{- end }}

{{/*
The CSI drivers this release must mount in addition to the pod's own, collected from the
enabled spiffe auth plugins. Deduplicated, so two plugins naming the same driver share one
volume. Returns JSON of driver name -> volume name; callers pipe it through fromJson.
*/}}
{{- define "spire-identity-exchange.extra-csi-drivers" -}}
{{-   $root := . }}
{{-   $drivers := dict }}
{{-   $volumeNames := dict }}
{{-   range $name, $config := .Values.auth.plugins }}
{{-     $config = $config | default dict }}
{{-     if ne (dig "enabled" true $config) false }}
{{-       $pluginType := include "spire-identity-exchange.plugin-type" (dict "root" $root "name" $name "config" $config) }}
{{-       $driver := dig "csiDriverName" "" $config }}
{{-       if and (eq $pluginType "spiffe") (not (empty $driver)) }}
{{-         if not (kindIs "string" $driver) }}
{{-           fail (printf "auth.plugins.%s.csiDriverName: expected string, got %s" $name (kindOf $driver)) }}
{{-         end }}
{{-         if ne $driver $root.Values.csiDriverName }}
{{-           $volumeName := include "spire-identity-exchange.csi-volume-name" $driver }}
{{-           if and (hasKey $volumeNames $volumeName) (ne (index $volumeNames $volumeName) $driver) }}
{{-             fail (printf "auth.plugins.%s.csiDriverName: %q and %q both reduce to the volume name %q. Volume names allow only lowercase alphanumerics and dashes, so these two drivers cannot be told apart; rename one so they differ by more than punctuation." $name $driver (index $volumeNames $volumeName) $volumeName) }}
{{-           end }}
{{-           $_ := set $volumeNames $volumeName $driver }}
{{-           $_ := set $drivers $driver $volumeName }}
{{-         end }}
{{-       end }}
{{-     end }}
{{-   end }}
{{-   $drivers | toJson }}
{{- end }}

{{- define "spire-identity-exchange.podSecurityContext" -}}
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

{{- define "spire-identity-exchange.server.namespace" -}}
{{-   if .Values.server.namespaceOverride -}}
{{-     .Values.server.namespaceOverride -}}
{{-   else if and (dig "spire" "recommendations" "enabled" false .Values.global) (dig "spire" "recommendations" "namespaceLayout" true .Values.global) }}
{{-     if ne (len (dig "spire" "namespaces" "server" "name" "" .Values.global)) 0 }}
{{-       .Values.global.spire.namespaces.server.name }}
{{-     else }}
{{-       printf "spire-server" }}
{{-     end }}
{{-   else -}}
{{-     .Release.Namespace -}}
{{-   end -}}
{{- end -}}

{{- define "spire-identity-exchange.server-address" }}
{{-   if and (ne (len (dig "spire" "upstreamSpireAddress" "" .Values.global)) 0) .Values.upstream }}
{{-     print .Values.global.spire.upstreamSpireAddress }}
{{-   else if .Values.server.address }}
{{-     .Values.server.address }}
{{-   else if .Values.server.nameOverride }}
{{     .Release.Name }}-{{ .Values.server.nameOverride }}.{{ include "spire-identity-exchange.server.namespace" . }}
{{-   else }}
{{     .Release.Name }}-server.{{ include "spire-identity-exchange.server.namespace" . }}
{{-   end }}
{{- end }}

{{- define "spire-identity-exchange.plugin-type" }}
{{-   $type := .name }}
{{-   with .config.plugin }}
{{-     $type = . }}
{{-   end }}
{{-   if not (has $type (list "k8s_psat" "spiffe" "github" "gitlab" )) }}
{{-     fail (printf "Unknown plugin type specified: %s" $type) }}
{{-   end }}
{{-   printf "%s" $type }}
{{- end }}

{{/*
Validate one plugin's config block against the option table for its type.
Emits nothing; only fails.
Args: dict "name" <instance name> "type" <plugin type> "config" <config map>
           "options" <dict of option name -> "string" | "[]string" | "bool">
*/}}
{{- define "spire-identity-exchange.check-plugin-options" }}
{{-   $ctx := . }}
{{-   $valid := keys $ctx.options | sortAlpha | join ", " }}
{{-   range $key, $val := $ctx.config }}
{{-     if not (hasKey $ctx.options $key) }}
{{-       fail (printf "auth.plugins.%s.config: %q is not a valid option for plugin type %q (valid options: %s). Use auth.unsupportedBuiltInPlugins to pass through options this chart does not model." $ctx.name $key $ctx.type $valid) }}
{{-     end }}
{{-     $want := index $ctx.options $key }}
{{-     if eq $want "[]string" }}
{{-       if not (kindIs "slice" $val) }}
{{-         fail (printf "auth.plugins.%s.config.%s: expected a list of strings, got %s" $ctx.name $key (kindOf $val)) }}
{{-       end }}
{{-       range $val }}
{{-         if not (kindIs "string" .) }}
{{-           fail (printf "auth.plugins.%s.config.%s: every entry must be a string, got %s" $ctx.name $key (kindOf .)) }}
{{-         end }}
{{-       end }}
{{-     else if not (kindIs $want $val) }}
{{-       fail (printf "auth.plugins.%s.config.%s: expected %s, got %s" $ctx.name $key $want (kindOf $val)) }}
{{-     end }}
{{-   end }}
{{- end }}

{{/*
Fail if any of the named options is absent or empty. Emits nothing.
Args: dict "name" <instance name> "type" <plugin type> "config" <config map>
           "required" <list of option names>
*/}}
{{- define "spire-identity-exchange.check-plugin-required" }}
{{-   $ctx := . }}
{{-   range $ctx.required }}
{{-     if empty (index $ctx.config .) }}
{{-       fail (printf "auth.plugins.%s.config.%s is required for plugin type %q" $ctx.name . $ctx.type) }}
{{-     end }}
{{-   end }}
{{- end }}
