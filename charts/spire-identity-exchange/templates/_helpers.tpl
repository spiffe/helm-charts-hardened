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

{{- define "spire-identity-exchange.server-address" }}
{{- if and (ne (len (dig "spire" "upstreamSpireAddress" "" .Values.global)) 0) .Values.upstream }}
{{- print .Values.global.spire.upstreamSpireAddress }}
{{- else if .Values.server.address }}
{{- .Values.server.address }}
{{- else if .Values.server.nameOverride }}
{{ .Release.Name }}-{{ .Values.server.nameOverride }}.{{ include "spire-agent.server.namespace" . }}
{{- else }}
{{ .Release.Name }}-server.{{ include "spire-agent.server.namespace" . }}
{{- end }}
{{- end }}
