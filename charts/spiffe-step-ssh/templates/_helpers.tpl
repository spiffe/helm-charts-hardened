{{/*
Expand the name of the chart.
*/}}
{{- define "spiffe-step-ssh.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "spiffe-step-ssh.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "spiffe-step-ssh.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "spiffe-step-ssh.labels" -}}
helm.sh/chart: {{ include "spiffe-step-ssh.chart" . }}
{{ include "spiffe-step-ssh.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "spiffe-step-ssh.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spiffe-step-ssh.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "spiffe-step-ssh.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "spiffe-step-ssh.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Takes in a dictionary with keys:
 * global - the standard global object
 * ingress - a standard format ingress config object
*/}}
{{- define "spiffe-step-ssh.ingress-controller-type" }}
{{-   $type := "" }}
{{-   if ne (len (dig "spiffe" "ingressControllerType" "" .global)) 0 }}
{{-     $type = .global.spiffe.ingressControllerType }}
{{-   else if ne .ingress.controllerType "" }}
{{-     $type = .ingress.controllerType }}
{{-   else if (dig "openshift" false .global) }}
{{-     $type = "openshift" }}
{{-   else }}
{{-     $type = "other" }}
{{-   end }}
{{-   if not (has $type (list "ingress-nginx" "openshift" "other")) }}
{{-     fail "Unsupported ingress controller type specified. Must be one of [ingress-nginx, openshift, other]" }}
{{-   end }}
{{-   $type }}
{{- end }}
