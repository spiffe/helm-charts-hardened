{{/* 15-char-safe port-name suffix for a controller-manager cluster name ("" -> ""). Shared by container ports and the PodMonitor so they cannot drift. */}}
{{- define "spire-controller-manager.portSuffix" -}}
{{- $name := . -}}
{{- $portSuffix := "" -}}
{{- if ne $name "" -}}
{{-   $portSuffix = printf "-%s" $name -}}
{{-   if gt (len $name) 9 -}}
{{-     $numberMatch := regexFind "[-]?[0-9]{1,2}$" $name -}}
{{-     if $numberMatch -}}
{{-       $numLen := len $numberMatch -}}
{{-       $baseLen := sub (len $name) $numLen | int -}}
{{-       $baseName := substr 0 $baseLen $name -}}
{{-       if not (hasPrefix "-" $numberMatch) -}}
{{-         $numberMatch = printf "-%s" $numberMatch -}}
{{-       end -}}
{{-       $maxBase := sub 9 (len $numberMatch) | int -}}
{{-       $baseName = $baseName | trunc $maxBase | trimSuffix "-" -}}
{{-       $portSuffix = printf "-%s%s" $baseName $numberMatch -}}
{{-     else -}}
{{-       $hash := sha256sum $name | trunc 3 -}}
{{-       $portSuffix = printf "-%s-%s" ($name | trunc 5 | trimSuffix "-") $hash -}}
{{-     end -}}
{{-   end -}}
{{- end -}}
{{- $portSuffix -}}
{{- end -}}

{{/* Resolve a port name: override wins, else prefix+suffix. dict: prefix, portSuffix, override */}}
{{- define "spire-controller-manager.portName" -}}
{{- if and (hasKey . "override") (ne (.override | toString) "") -}}
{{- .override -}}
{{- else -}}
{{- printf "%s%s" .prefix .portSuffix -}}
{{- end -}}
{{- end -}}

{{/* Prometheus port name for one controller-manager. dict: name (""=main), settings (may hold prometheusPortName) */}}
{{- define "spire-controller-manager.promPortName" -}}
{{- $override := "" -}}
{{- if hasKey .settings "prometheusPortName" -}}
{{-   $override = .settings.prometheusPortName -}}
{{- end -}}
{{- include "spire-controller-manager.portName" (dict "prefix" "pm-cm" "portSuffix" (include "spire-controller-manager.portSuffix" .name) "override" $override) -}}
{{- end -}}

{{/* List of prometheus port names for every controller-manager that renders one. Consumed by the PodMonitor. */}}
{{- define "spire-controller-manager.prometheusPortNames" -}}
{{- $root := . -}}
{{- $names := list -}}
{{- if eq (.Values.controllerManager.enabled | toString) "true" -}}
{{-   if ne .Values.controllerManager.deploymentMode "standalone" -}}
{{-     $names = append $names (include "spire-controller-manager.promPortName" (dict "name" "" "settings" .Values.controllerManager)) -}}
{{-   end -}}
{{- end -}}
{{- if .Values.externalControllerManagers.enabled -}}
{{-   $clusters := default .Values.kubeConfigs .Values.externalControllerManagers.clusters -}}
{{-   range $name, $_ := $clusters -}}
{{-     $clusterSettings := dict -}}
{{-     if hasKey $root.Values.externalControllerManagers.clusters $name -}}
{{-       $clusterSettings = index $root.Values.externalControllerManagers.clusters $name -}}
{{-     end -}}
{{-     $pmName := include "spire-controller-manager.promPortName" (dict "name" $name "settings" $clusterSettings) -}}
{{-     if has $pmName $names -}}
{{-       fail (printf "controller-manager prometheus port name %q collides for cluster %q; set a distinct prometheusPortName override" $pmName $name) -}}
{{-     end -}}
{{-     $names = append $names $pmName -}}
{{-   end -}}
{{- end -}}
{{- $names | toYaml -}}
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
{{-     if not (has .Values.controllerManager.deploymentMode (list "sidecar" "standalone")) }}
{{-       fail "controllerManager.deploymentMode must be one of \"sidecar\" or \"standalone\"" }}
{{-     end }}
{{-     if eq .Values.controllerManager.deploymentMode "standalone" }}
{{/*
In standalone mode, the controller manager runs entirely in its own
Deployment (see controller-manager-standalone.yaml), connecting to the
SPIRE Server over TCP. Nothing is rendered here in the spire-server Pod
at all - the spire-server Pod's shape is unaffected by the controller
manager (see issue #341). The standalone Deployment obtains its own
SPIFFE identity via its own in-pod spire-agent sidecar (attested as a
distinct k8s_psat node via use_pod_uid_for_agent_id, see configmap.yaml)
plus a node-alias registration entry created by a postStart hook on the
spire-server container (see server-resource.yaml) - both are fully
static/computable ahead of time, so no chicken-and-egg bootstrap
container/CR is needed.
*/}}
{{-     else }}
{{-       if .Values.controllerManager.reconcile.clusterFederatedTrustDomains }}
{{-         $reconcileFederation = add $reconcileFederation 1 }}
{{-       end }}
{{-       if or .Values.controllerManager.reconcile.clusterSPIFFEIDs .Values.controllerManager.reconcile.clusterStaticEntries }}
{{-         $reconcileEntries = add $reconcileEntries 1 }}
{{-       end }}
{{-       include "spire-controller-manager.container" (dict "Values" .Values "Chart" .Chart "startPort" $startPort "suffix" "" "portSuffix" "" "healthPortName" "" "prometheusPortName" "" "settings" $settings "defaults" $defaults "webhooksEnabled" $webhooksEnabled) }}
{{-     end }}
{{-   end }}
{{-   if .Values.externalControllerManagers.enabled }}
{{-     $clusters := default .Values.kubeConfigs .Values.externalControllerManagers.clusters }}
{{-     $clusterDefaults := .Values.externalControllerManagers.defaults }}
{{-     range $name, $_ := $clusters }}
{{-       $clusterSettings := dict }}
{{-       if hasKey $root.Values.externalControllerManagers.clusters $name }}
{{-         $clusterSettings = index $root.Values.externalControllerManagers.clusters $name }}
{{-       end }}

{{/*
Generate port names for controller-manager ports.
Can be explicitly set via healthPortName and prometheusPortName in cluster configuration.
Otherwise uses default prefixes (hp-cm/pm-cm) with auto-generated suffixes.
Auto-generation preserves trailing numbers from cluster names or uses hash for uniqueness.
*/}}
{{-       $suffix := printf "-%s" $name }}
{{-       $portSuffix := $suffix }}
{{-       $healthPortName := "" }}
{{-       $prometheusPortName := "" }}
{{-       if hasKey $clusterSettings "healthPortName" }}
{{-         $healthPortName = $clusterSettings.healthPortName }}
{{-       end }}
{{-       if hasKey $clusterSettings "prometheusPortName" }}
{{-         $prometheusPortName = $clusterSettings.prometheusPortName }}
{{-       end }}
{{-       if or (eq $healthPortName "") (eq $prometheusPortName "") }}
{{-         $portSuffix = include "spire-controller-manager.portSuffix" $name }}
{{-       end }}

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
{{-       include "spire-controller-manager.container" (dict "Values" $root.Values "Chart" $root.Chart "startPort" $startPort "suffix" $suffix "portSuffix" $portSuffix "healthPortName" $healthPortName "prometheusPortName" $prometheusPortName "settings" $clusterSettings "defaults" $clusterDefaults "webhooksEnabled" false "kubeConfig" $kubeConfig ) }}
{{-     end }}
{{-   end }}
{{- end }}
{{- define "spire-controller-manager.container" }}
{{-   $promPort := .startPort }}
{{-   $healthPort := add .startPort 1 }}
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
- name: spire-controller-manager{{ .suffix }}
  securityContext:
    {{- include "spire-lib.securitycontext-extended" (dict "root" . "securityContext" $securityContext) | nindent 4 }}
  image: {{ template "spire-lib.image" (dict "appVersion" .Chart.AppVersion "image" .Values.controllerManager.image "global" .Values.global) }}
  imagePullPolicy: {{ .Values.controllerManager.image.pullPolicy }}
  args:
    {{- if hasKey . "kubeConfig" }}
    - --kubeconfig=/kubeconfigs/{{ .kubeConfig }}
    {{- end }}
    - --config=controller-manager-config{{ .suffix }}.yaml
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
  {{/* Port names: hp-cm (health), pm-cm (prometheus) - abbreviated for 15 char limit */}}
  {{/* Can be overridden via healthPortName and prometheusPortName in cluster config */}}
  ports:
    {{- if .webhooksEnabled }}
    - name: https
      containerPort: 9443
      protocol: TCP
    {{- end }}
    {{- $hpName := include "spire-controller-manager.portName" (dict "prefix" "hp-cm" "portSuffix" .portSuffix "override" .healthPortName) }}
    - containerPort: {{ $healthPort }}
      name: {{ $hpName }}
    {{- if or (dig "telemetry" "prometheus" "enabled" .Values.telemetry.prometheus.enabled .Values.global) (and (dig "spire" "recommendations" "enabled" false .Values.global) (dig "spire" "recommendations" "prometheus" true .Values.global)) }}
    {{-   $pmName := include "spire-controller-manager.portName" (dict "prefix" "pm-cm" "portSuffix" .portSuffix "override" .prometheusPortName) }}
    - containerPort: {{ $promPort }}
      name: {{ $pmName }}
    {{- end }}
{{- if eq .Values.controllerManager.staticManifestMode "off" }}
  livenessProbe:
    httpGet:
      path: /healthz
      port: {{ $hpName }}
    {{- toYaml .Values.controllerManager.livenessProbe | nindent 4 }}
  {{- if not (.noReadinessProbe | default false) }}
  readinessProbe:
    httpGet:
      path: /readyz
      port: {{ $hpName }}
    {{- toYaml .Values.controllerManager.readinessProbe | nindent 4 }}
  {{- end }}
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
      mountPath: /controller-manager-config{{ .suffix }}.yaml
      subPath: controller-manager-config{{ .suffix }}.yaml
      readOnly: true
    {{- with .kubeConfig }}
    - name: kubeconfigs
      mountPath: /kubeconfigs/{{ . }}
      subPath: {{ . }}
      readOnly: true
    {{- end }}
    {{- if hasKey . "kubeConfig" }}
    {{-   $entry := default dict (index .Values.kubeConfigs .kubeConfig) }}
    {{-   if hasKey $entry "jwtSVIDExec" }}
    - name: plugins
      mountPath: /plugins
      readOnly: true
    {{-   end }}
    {{- end }}
    - name: spire-controller-manager-tmp
      mountPath: /tmp
      subPath: {{ printf "spire-controller-manager%s" .suffix }}
      readOnly: false
    {{- if gt (len .Values.extraVolumeMounts) 0 }}
    {{- toYaml .Values.extraVolumeMounts | nindent 4 }}
    {{- end }}
{{- end }}
