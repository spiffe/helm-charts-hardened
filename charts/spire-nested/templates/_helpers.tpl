{{/*
Expand the name of the chart.
*/}}
{{- define "spire-nested.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "spire-nested.fullname" -}}
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

{{- define "spire-nested.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "spire-nested.labels" -}}
helm.sh/chart: {{ include "spire-nested.chart" . }}
app.kubernetes.io/name: {{ include "spire-nested.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
The namespace the SPIRE server side components land in. Resolved the same way as
spire-identity-exchange.namespace, so the combined exposure lands beside the exchange
pods it selects — a Service selector is namespace scoped.
*/}}
{{- define "spire-nested.server-namespace" -}}
  {{- if and (dig "spire" "recommendations" "enabled" false .Values.global) (dig "spire" "recommendations" "namespaceLayout" true .Values.global) }}
    {{- if ne (len (dig "spire" "namespaces" "server" "name" "" .Values.global)) 0 }}
      {{- .Values.global.spire.namespaces.server.name }}
    {{- else }}
      {{- printf "spire-server" }}
    {{- end }}
  {{- else -}}
    {{- .Release.Namespace -}}
  {{- end -}}
{{- end -}}

{{/*
Base name for the combined identity exchange objects. Keyed on the release name so it
reads like the per-side exchanges, which the sides' own releases name spire-a-identity-
exchange / spire-b-identity-exchange — so these never collide with them either.
*/}}
{{- define "spire-nested.identity-exchange-name" -}}
{{- printf "%s-identity-exchange" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
