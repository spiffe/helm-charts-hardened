{{- define "valid-service-name" -}}
{{- $name := . -}}
{{- /* Set the max length of the suffix to ensure total length is at most 15 characters */ -}}
{{- $maxLength := 7 -}}
{{- if gt (len $name) $maxLength -}}
{{- $name = substr $name 0 $maxLength -}}
{{- end -}}
{{- /* Replace or sanitize any invalid characters to ensure RFC compliance */ -}}
{{- $name = regexReplaceAll "[^a-zA-Z0-9-]" $name "-" -}}
{{- $name = regexReplaceAll "^-+|-+$" $name "" -}}  {{/* Remove leading or trailing hyphens */ -}}
{{- $name = regexReplaceAll "--+" $name "-" -}}    {{/* Replace multiple hyphens with a single one */ -}}
{{- if not (regexMatch "[a-zA-Z]" $name) -}}       {{/* Ensure it contains at least one letter */ -}}
{{- fail "The resulting name must contain at least one letter (A-Z or a-z)." -}}
{{- end -}}
{{- if eq (len $name) 0 -}}
{{- fail "The resulting name must be at least 1 character long." -}}
{{- end -}}
{{- $name -}}
{{- end -}}

{{- define "spire-controller-manager.containers" }}
{{-   $root := . }}
{{-   $settings := dict }}
{{-   $defaults := .Values.controllerManager }}
{{-   $webhooksEnabled := .Values.controllerManager.validatingWebhookConfiguration.enabled }}
{{-   $startPort := 8082 }}
{{-   $reconcileFederation := 0 }}
{{-   $reconcileEntries := 0 }}
{{-   if eq (.Values.controllerManager.enabled | toString) "true" }}
{{-     if .Values.controllerManager.reconcile.clusterFederatedTrustDomains }}
{{-       $reconcileFederation = add $reconcileFederation 1 }}
{{-     end }}
{{-     if or .Values.controllerManager.reconcile.clusterSPIFFEIDs .Values.controllerManager.reconcile.clusterStaticEntries }}
{{-       $reconcileEntries = add $reconcileEntries 1 }}
{{-     end }}
{{-     include "spire-controller-manager.container" (dict "Values" .Values "Chart" .Chart "startPort" $startPort "suffix" "" "settings" $settings "defaults" $defaults "webhooksEnabled" $webhooksEnabled) }}
{{-   end }}
{{-   if .Values.externalControllerManagers.enabled }}
{{-     $clusters := default .Values.kubeConfigs .Values.externalControllerManagers.clusters }}
{{-     $clusterDefaults := .Values.externalControllerManagers.defaults }}
{{-     range $name, $_ := $clusters }}
{{-       $clusterSettings := dict }}
{{-       if hasKey $root.Values.externalControllerManagers.clusters $name }}
{{-         $clusterSettings = index $root.Values.externalControllerManagers.clusters $name }}
{{-       end }}
{{-       $suffix := printf "-%s" $name }}
{{-       $startPort = add $startPort 2 }}
{{-       $kubeConfig := $name }}
{{-       if hasKey $clusterSettings "kubeConfigName" }}
{{-         $kubeConfig = $clusterSettings.kubeConfigName }}
{{-       end }}
{{-       $reconcile := dict }}
{{-       if hasKey $clusterSettings "reconcile" }}
{{-         $reconcile = $clusterSettings.reconcile }}
{{-       end }}
{{-       if and (hasKey $reconcile "clusterFederatedTrustDomains") $reconcile.clusterFederatedTrustDomains }}
{{-         $reconcileFederation = add $reconcileFederation 1 }}
{{-       else if $clusterDefaults.reconcile.clusterFederatedTrustDomains }}
{{-         $reconcileFederation = add $reconcileFederation 1 }}
{{-       end }}
{{-       if gt $reconcileFederation 1 }}
{{-         fail "You can only have one controller-manager with reconcile.clusterFederatedTrustDomains set to true" }}
{{-       end }}
{{-       include "spire-controller-manager.container" (dict "Values" $root.Values "Chart" $root.Chart "startPort" $startPort "suffix" $suffix "settings" $clusterSettings "defaults" $clusterDefaults "webhooksEnabled" false "kubeConfig" $kubeConfig ) }}
{{-     end }}
{{-   end }}
{{- end }}
{{- define "spire-controller-manager.container" }}
{{-   $promPort := .startPort }}
{{-   $healthPort := add .startPort 1 }}
{{-   $sanitizedSuffix := include "valid-service-name" .suffix }}
{{-   $extraEnv := .defaults.extraEnv }}
{{-   if hasKey .settings "extraEnv" }}
{{-     $extraEnv = .settings.extraEnv }}
{{-   end }}
{{-   $expandEnv := .defaults.expandEnv }}
{{-   if hasKey .settings "expandEnv" }}
{{-     $extraEnv = .settings.expandEnv }}
{{-   end }}
{{-   $securityContext := .defaults.securityContext }}
{{-   if hasKey .settings "securityContext" }}
{{-     $securityContext = mergeOverwrite .defaults.securityContext .settings.securityContext }}
{{-   end }}
- name: spire-controller-manager{{ $sanitizedSuffix }}
  securityContext:
    {{- include "spire-lib.securitycontext-extended" (dict "root" . "securityContext" $securityContext) | nindent 4 }}
  image: {{ template "spire-lib.image" (dict "appVersion" .Chart.AppVersion "image" .Values.controllerManager.image "global" .Values.global) }}
  imagePullPolicy: {{ .Values.controllerManager.image.pullPolicy }}
  args:
    {{- if hasKey . "kubeConfig" }}
    - --kubeconfig=/kubeconfigs/{{ .kubeConfig }}
    {{- end }}
    - --config=controller-manager-config{{ $sanitizedSuffix }}.yaml
    {{- if $expandEnv }}
    - --expand-env
    {{- end }}
  env:
    - name: ENABLE_WEBHOOKS
    {{- if eq .Values.controllerManager.staticManifestMode "off" }}
      value: {{ .webhooksEnabled | toString | quote }}
    {{- else }}
      value: "false"
    {{- end }}
  {{- if gt (len $extraEnv) 0 }}
  {{-   $extraEnv | toYaml | nindent 4 }}
  {{- end }}
  ports:
    {{- if .webhooksEnabled }}
    - name: https
      containerPort: 9443
      protocol: TCP
    {{- end }}
    - containerPort: {{ $healthPort }}
      name: healthz
    {{- if or (dig "telemetry" "prometheus" "enabled" .Values.telemetry.prometheus.enabled .Values.global) (and (dig "spire" "recommendations" "enabled" false .Values.global) (dig "spire" "recommendations" "prometheus" true .Values.global)) }}
    - containerPort: {{ $promPort }}
      name: prom-cm-{{ $sanitizedSuffix }}
    {{- end }}
{{- if eq .Values.controllerManager.staticManifestMode "off" }}
  livenessProbe:
    httpGet:
      path: /healthz
      port: healthz
  readinessProbe:
    httpGet:
      path: /readyz
      port: healthz
{{- end }}
  resources:
    {{- toYaml .Values.controllerManager.resources | nindent 4 }}
  volumeMounts:
    - name: spire-server-socket
      mountPath: /tmp/spire-server/private
      readOnly: true
    {{- if ne .Values.controllerManager.staticManifestMode "off" }}
    - name: controller-manager-static-config
      mountPath: /manifests
    {{- end }}
    - name: controller-manager-config
      mountPath: /controller-manager-config{{ $sanitizedSuffix }}.yaml
      subPath: controller-manager-config{{ $sanitizedSuffix }}.yaml
      readOnly: true
    {{- with .kubeConfig }}
    - name: kubeconfigs
      mountPath: /kubeconfigs/{{ . }}
      subPath: {{ . }}
      readOnly: true
    {{- end }}
    - name: spire-controller-manager-tmp
      mountPath: /tmp
      subPath: {{ printf "spire-controller-manager%s" $sanitizedSuffix }}
      readOnly: false
    {{- if gt (len .Values.extraVolumeMounts) 0 }}
    {{- toYaml .Values.extraVolumeMounts | nindent 4 }}
    {{- end }}
{{- end }}
