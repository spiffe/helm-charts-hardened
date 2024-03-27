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
      value: {{ .webhooksEnabled | toString | quote }}
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
      name: prom-cm{{ .suffix }}
    {{- end }}
  livenessProbe:
    httpGet:
      path: /healthz
      port: healthz
  readinessProbe:
    httpGet:
      path: /readyz
      port: healthz
  resources:
    {{- toYaml .Values.controllerManager.resources | nindent 4 }}
  volumeMounts:
    - name: spire-server-socket
      mountPath: /tmp/spire-server/private
      readOnly: true
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
    - name: spire-controller-manager-tmp
      mountPath: /tmp
      subPath: {{ printf "spire-controller-manager%s" .suffix }}
      readOnly: false
    {{- if gt (len .Values.extraVolumeMounts) 0 }}
    {{- toYaml .Values.extraVolumeMounts | nindent 4 }}
    {{- end }}
{{- end }}
