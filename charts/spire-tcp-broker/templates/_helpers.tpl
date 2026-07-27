{{/*
Expand the name of the chart.
*/}}
{{- define "spire-tcp-broker.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "spire-tcp-broker.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Use the Helm release namespace for all namespaced resources. */}}
{{- define "spire-tcp-broker.namespace" -}}
{{- .Release.Namespace -}}
{{- end -}}

{{/* Create a collision-resistant base name for cluster-scoped resources. */}}
{{- define "spire-tcp-broker.cluster-fullname" -}}
{{- printf "%s-%s" (include "spire-tcp-broker.namespace" .) (include "spire-tcp-broker.fullname" .) }}
{{- end }}

{{/* Prefix user-provided RBAC names with the owning release identity. */}}
{{- define "spire-tcp-broker.rbac-name" -}}
{{- printf "%s-%s" (include "spire-tcp-broker.cluster-fullname" .root) .name }}
{{- end }}

{{/* Resolve the workload namespace for a Broker. */}}
{{- define "spire-tcp-broker.broker-namespace" -}}
{{- default (include "spire-tcp-broker.namespace" .root) .broker.namespace }}
{{- end }}

{{/* Resolve the workload service account name for a Broker. */}}
{{- define "spire-tcp-broker.broker-service-account-name" -}}
{{- default .broker.name .broker.serviceAccountName }}
{{- end }}

{{/* Create the ClusterStaticEntry name for a Broker. */}}
{{- define "spire-tcp-broker.broker-entry-name" -}}
{{- printf "%s-%s-entry" (include "spire-tcp-broker.cluster-fullname" .root) .broker.name }}
{{- end }}


{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "spire-tcp-broker.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels */}}
{{- define "spire-tcp-broker.labels" -}}
helm.sh/chart: {{ include "spire-tcp-broker.chart" . | quote }}
{{ include "spire-tcp-broker.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
{{- end }}

{{/* Selector labels */}}
{{- define "spire-tcp-broker.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spire-tcp-broker.name" . | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
{{- end }}



{{- define "spire-tcp-broker.broker-kubernetes-object-reference-type" -}}
type.googleapis.com/spiffe.broker.KubernetesObjectReference
{{- end }}

{{- define "spire-tcp-broker.broker-id" -}}
spiffe://{{ include "spire-lib.trust-domain" .root }}/{{ .broker.name }}
{{- end }}

{{- define "spire-tcp-broker.agent-alias-id" -}}
spiffe://{{ include "spire-lib.trust-domain" . }}/agent-alias/tcp-broker/{{ include "spire-tcp-broker.cluster-fullname" . }}
{{- end }}

{{/* Normalize a static entry path to be relative to the trust domain. */}}
{{- define "spire-tcp-broker.static-entry-path" -}}
{{- trimPrefix "/" (default "" .entry.path | toString) -}}
{{- end }}

{{/* Build the SPIFFE ID for a static entry. */}}
{{- define "spire-tcp-broker.static-entry-id" -}}
spiffe://{{ include "spire-lib.trust-domain" .root }}/{{ include "spire-tcp-broker.static-entry-path" . }}
{{- end }}

{{/* Create a stable, release-unique cluster-scoped name from a static entry path. */}}
{{- define "spire-tcp-broker.static-entry-name" -}}
{{- $path := include "spire-tcp-broker.static-entry-path" . -}}
{{- printf "%s-static-entry-%s" (include "spire-tcp-broker.cluster-fullname" .root) (sha256sum $path | trunc 16) -}}
{{- end }}

{{- define "spire-tcp-broker.server-id" -}}
spiffe://{{ include "spire-lib.trust-domain" . }}/spire/server
{{- end }}
