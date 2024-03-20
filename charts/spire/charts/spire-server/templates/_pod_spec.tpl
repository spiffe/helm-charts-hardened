{{- define "spire-server.pod-spec" -}}
spec:
  {{- with .Values.imagePullSecrets }}
  imagePullSecrets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  serviceAccountName: {{ include "spire-server.serviceAccountName" . }}
  shareProcessNamespace: true
  securityContext:
    {{- include "spire-lib.podsecuritycontext" . | nindent 4 }}
  {{- include "spire-lib.default_cluster_priority_class_name" . | nindent 2 }}
  {{- if or (gt (len .Values.initContainers) 0) (and .Values.upstreamAuthority.certManager.enabled .Values.upstreamAuthority.certManager.ca.create) .Values.nodeAttestor.tpmDirect.enabled }}
  initContainers:
    {{- if .Values.nodeAttestor.tpmDirect.enabled }}
    - name: init-tpm-direct
      securityContext:
        {{- include "spire-lib.securitycontext" . | nindent 8 }}
      image: {{ template "spire-lib.image" (dict "appVersion" $.Chart.AppVersion "image" .Values.nodeAttestor.tpmDirect.image "global" .Values.global) }}
      command:
        - sh
        - -ec
        - |
          # SPIRE must be able to fork the plugin directly within its container. Copy the plugin into a volume that can be mounted where SPIRE can execute it.
          cp -a {{ .Values.nodeAttestor.tpmDirect.pluginPath }} /tpm/tpm_attestor_server
          mkdir -p /run/spire/data/tpm-direct/certs
          mkdir -p /run/spire/data/tpm-direct/hashes
      volumeMounts:
        - name: tpm-direct
          mountPath: /tpm
        - name: spire-data
          mountPath: /run/spire/data
      imagePullPolicy: {{ .Values.nodeAttestor.tpmDirect.image.pullPolicy }}
  {{- end }}
  {{- if and .Values.upstreamAuthority.certManager.enabled .Values.upstreamAuthority.certManager.ca.create }}
    - name: wait
      securityContext:
        {{- include "spire-lib.securitycontext" . | nindent 8 }}
      image: {{ template "spire-lib.kubectl-image" (dict "appVersion" $.Chart.AppVersion "image" .Values.tools.kubectl.image "global" .Values.global "KubeVersion" .Capabilities.KubeVersion.Version) }}
      args:
        - wait
        - --namespace
        - {{ .Release.Namespace }}
        - --timeout=3m
        - --for=condition=ready
        - issuer
        - {{ include "spire-server.fullname" $ }}-ca
      imagePullPolicy: {{ .Values.tools.kubectl.image.pullPolicy }}
  {{- end }}
  {{- if gt (len .Values.initContainers) 0 }}
    {{- toYaml .Values.initContainers | nindent 4 }}
  {{- end }}
  {{- end }}
  containers:
    - name: {{ .Chart.Name }}
      securityContext:
        {{- include "spire-lib.securitycontext" . | nindent 8 }}
      image: {{ template "spire-lib.image" (dict "appVersion" $.Chart.AppVersion "image" .Values.image "global" .Values.global) }}
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      args:
        - -expandEnv
        - -config
        - /run/spire/config/server.conf
      env:
      - name: PATH
        value: "/opt/spire/bin:/bin"
      {{- with .Values.extraEnv }}
      {{- . | toYaml | nindent 6 }}
      {{- end }}
      {{- if ne .Values.dataStore.sql.databaseType "sqlite3" }}
      {{- if .Values.dataStore.sql.externalSecret.enabled }}
      - name: DBPW
        valueFrom:
          secretKeyRef:
            name: {{ .Values.dataStore.sql.externalSecret.name }}
            key: {{ .Values.dataStore.sql.externalSecret.key }}
      {{- else }}
      - name: DBPW
        valueFrom:
          secretKeyRef:
            name: {{ include "spire-server.fullname" . }}-dbpw
            key: DBPW
      {{- end }}
      {{- end }}
      {{- if ne .Values.keyManager.awsKMS.accessKeyID "" }}
      - name: AWS_KMS_ACCESS_KEY_ID
        valueFrom:
          secretKeyRef:
            name: {{ include "spire-server.fullname" . }}-aws-kms
            key: AWS_KMS_ACCESS_KEY_ID
      {{- end }}
      {{- if ne .Values.keyManager.awsKMS.secretAccessKey "" }}
      - name: AWS_KMS_SECRET_ACCESS_KEY
        valueFrom:
          secretKeyRef:
            name: {{ include "spire-server.fullname" . }}-aws-kms
            key: AWS_KMS_SECRET_ACCESS_KEY
      {{- end }}
      ports:
        - name: grpc
          containerPort: 8081
          protocol: TCP
        - containerPort: 8080
          name: healthz
        {{- with .Values.federation }}
        {{- if eq (.enabled | toString) "true" }}
        - name: federation
          containerPort: {{ .bundleEndpoint.port }}
          protocol: TCP
        {{- end }}
        {{- end }}
        {{- if or (dig "telemetry" "prometheus" "enabled" .Values.telemetry.prometheus.enabled .Values.global) (and (dig "spire" "recommendations" "enabled" false .Values.global) (dig "spire" "recommendations" "prometheus" true .Values.global)) }}
        - containerPort: 9988
          name: prom
        {{- end }}
      livenessProbe:
        httpGet:
          path: /live
          port: healthz
        {{- toYaml .Values.livenessProbe | nindent 8 }}
      readinessProbe:
        httpGet:
          path: /ready
          port: healthz
        {{- toYaml .Values.readinessProbe | nindent 8 }}
      resources:
        {{- toYaml .Values.resources | nindent 8 }}
      volumeMounts:
        - name: spire-server-socket
          mountPath: /tmp/spire-server/private
          readOnly: false
        - name: spire-config
          mountPath: /run/spire/config
          readOnly: true
        - name: spire-data
          mountPath: /run/spire/data
          readOnly: false
        {{- with .Values.kubeConfigs }}
        - name: kubeconfigs
          mountPath: /kubeconfigs
          readOnly: true
        {{- end }}
        {{- if .Values.nodeAttestor.tpmDirect.enabled }}
        - name: tpm-direct
          mountPath: /tpm
          readOnly: true
        {{- if ne (len .Values.nodeAttestor.tpmDirect.cas) 0 }}
        - name: tpm-direct-cas
          mountPath: /tpm-direct-cas
        {{- end }}
        {{- if ne (len .Values.nodeAttestor.tpmDirect.hashes) 0 }}
        - name: tpm-direct-hashes
          mountPath: /tmp-direct-hashes
        {{- end }}
        {{- end }}
        {{- if eq (.Values.upstreamAuthority.disk.enabled | toString) "true" }}
        - name: upstream-ca
          mountPath: /run/spire/upstream_ca
          readOnly: false
        {{ end }}
        {{- if gt (len .Values.upstreamAuthority.spire.upstreamDriver) 0 }}
        - name: upstream-agent
          mountPath: /run/spire/upstream_agent
          readOnly: true
        {{ end }}
        {{- with .Values.keyManager.awsKMS }}
        {{- if and (eq (.enabled | toString) "true") (or (ne .keyPolicy.policy "") (ne .keyPolicy.existingConfigMap "")) }}
        - name: aws-kms-key-policy
          mountPath: /run/spire/data/aws-kms-key-policy.json
          subPath: policy.json
          readOnly: true
        {{ end }}
        {{- end }}
        {{- with .Values.upstreamAuthority.vault }}
        {{- if eq (.enabled | toString) "true" }}
        {{- if eq (.k8sAuth.enabled | toString) "true" }}
        - name: spire-psat
          mountPath: /var/run/secrets/tokens
        {{- end }}
        {{- if ne (.insecureSkipVerify | toString) "true" }}
        - name: vault-ca
          mountPath: /run/spire/vault-upstream
        {{- end }}
        {{- end }}
        {{- end }}
        {{- if gt (len .Values.extraVolumeMounts) 0 }}
        {{- toYaml .Values.extraVolumeMounts | nindent 8 }}
        {{- end }}
        - name: server-tmp
          mountPath: /tmp
          readOnly: false
    {{- if eq (.Values.controllerManager.enabled | toString) "true" }}
    - name: spire-controller-manager
      securityContext:
        {{- include "spire-lib.securitycontext-extended" (dict "root" . "securityContext" .Values.controllerManager.securityContext) | nindent 8 }}
      image: {{ template "spire-lib.image" (dict "appVersion" $.Chart.AppVersion "image" .Values.controllerManager.image "global" .Values.global) }}
      imagePullPolicy: {{ .Values.controllerManager.image.pullPolicy }}
      args:
        - --config=controller-manager-config.yaml
        {{- if .Values.controllerManager.expandEnv }}
        - --expand-env
        {{- end }}
      env:
        - name: ENABLE_WEBHOOKS
          value: {{ .Values.controllerManager.validatingWebhookConfiguration.enabled | toString | quote }}
      {{- if gt (len .Values.controllerManager.extraEnv) 0 }}
        {{- .Values.controllerManager.extraEnv | toYaml | nindent 8 }}
      {{- end }}
      ports:
        - name: https
          containerPort: 9443
          protocol: TCP
        - containerPort: 8083
          name: healthz
        {{- if or (dig "telemetry" "prometheus" "enabled" .Values.telemetry.prometheus.enabled .Values.global) (and (dig "spire" "recommendations" "enabled" false .Values.global) (dig "spire" "recommendations" "prometheus" true .Values.global)) }}
        - containerPort: 8082
          name: prom2
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
        {{- toYaml .Values.controllerManager.resources | nindent 8 }}
      volumeMounts:
        - name: spire-server-socket
          mountPath: /tmp/spire-server/private
          readOnly: true
        - name: controller-manager-config
          mountPath: /controller-manager-config.yaml
          subPath: controller-manager-config.yaml
          readOnly: true
        - name: spire-controller-manager-tmp
          mountPath: /tmp
          readOnly: false
        {{- if gt (len .Values.extraVolumeMounts) 0 }}
        {{- toYaml .Values.extraVolumeMounts | nindent 8 }}
        {{- end }}
    {{- end }}

    {{- if eq (.Values.tornjak.enabled | toString) "true" }}
    - name: tornjak
      securityContext:
        {{- include "spire-lib.securitycontext-extended" (dict "root" . "securityContext" .Values.tornjak.securityContext) | nindent 8 }}
      image: {{ template "spire-lib.image" (dict "appVersion" .Values.tornjak.image.defaultTag "image" .Values.tornjak.image "global" .Values.global "ubi" true) }}
      imagePullPolicy: {{ .Values.tornjak.image.pullPolicy }}
      {{- if eq (include "spire-tornjak.connectionType" .) "http" }}
      startupProbe:
        httpGet:
          scheme: HTTP
          path: /api/tornjak/serverinfo
          port: 10000
        {{- toYaml .Values.tornjak.startupProbe | nindent 8 }}
      {{- end }}
      args:
        - --spire-config
        - /run/spire/config/server.conf
        - --tornjak-config
        - /run/spire/tornjak-config/server.conf
      ports:
        - name: tornjak-http
          containerPort: 10000
          protocol: TCP
        - name: tornjak-https
          containerPort: 10443
          protocol: TCP
      resources:
        {{- toYaml .Values.tornjak.resources | nindent 8 }}
      volumeMounts:
        - name: {{ include "spire-tornjak.config" . }}
          mountPath: /run/spire/tornjak-config
        - name: spire-server-socket
          mountPath: /tmp/spire-server/private
          readOnly: true
        - name: spire-config
          mountPath: /run/spire/config
          readOnly: true
        - name: spire-data
          mountPath: /run/spire/data
          readOnly: false
        {{- if or (eq (include "spire-tornjak.connectionType" .) "tls") (eq (include "spire-tornjak.connectionType" .) "mtls") }}
        - name: server-cert
          mountPath: /opt/spire/server
        {{- end }}
        {{- if eq (include "spire-tornjak.connectionType" .) "mtls" }}
        - name: user-cert
          mountPath: /opt/spire/user
        {{- end }}
    {{- end }}

    {{- if gt (len .Values.extraContainers) 0 }}
    {{- toYaml .Values.extraContainers | nindent 4 }}
    {{- end }}
  {{- with .Values.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.affinity }}
  affinity:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.topologySpreadConstraints }}
  topologySpreadConstraints:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  volumes:
    - name: server-tmp
      emptyDir: {}
    - name: spire-config
      configMap:
        name: {{ include "spire-server.fullname" . }}
    - name: spire-server-socket
      emptyDir: {}
    - name: spire-controller-manager-tmp
      emptyDir: {}
    {{- if gt (len .Values.kubeConfigs) 0 }}
    - name: kubeconfigs
      secret:
        secretName: {{ include "spire-server.fullname" . }}-kubeconfigs
    {{- end }}
    {{- if .Values.nodeAttestor.tpmDirect.enabled }}
    - name: tpm-direct
      emptyDir: {}
    {{- if ne (len .Values.nodeAttestor.tpmDirect.cas) 0 }}
    - name: tpm-direct-cas
      configMap:
        name: {{ include "spire-server.fullname" . }}-tpm-direct-ca
    {{- end }}
    {{- if ne (len .Values.nodeAttestor.tpmDirect.hashes) 0 }}
    - name: tpm-direct-hashes
      configMap:
        name: {{ include "spire-server.fullname" . }}-tpm-direct-hash
    {{- end }}
    {{- end }}
    {{- if or (eq (include "spire-tornjak.connectionType" .) "tls") (eq (include "spire-tornjak.connectionType" .) "mtls") }}
    - name: server-cert
      secret:
        defaultMode: 256
        secretName: {{ .Values.tornjak.config.tlsSecret }}
    {{- end }}
    {{- if eq (include "spire-tornjak.connectionType" .) "mtls" }}
    {{- if eq .Values.tornjak.config.clientCA.type "Secret" }}
    - name: user-cert
      secret:
        defaultMode: 256
        secretName: {{ .Values.tornjak.config.clientCA.name }}
    {{- else if eq .Values.tornjak.config.clientCA.type "ConfigMap" }}
    - name: user-cert
      configMap:
        name: {{ .Values.tornjak.config.clientCA.name }}
    {{- end }}
    {{- end }}
    {{- if eq (.Values.upstreamAuthority.disk.enabled | toString) "true" }}
    - name: upstream-ca
      secret:
        secretName: {{ include "spire-server.upstream-ca-secret" . }}
    {{- end }}
    {{- if gt (len .Values.upstreamAuthority.spire.upstreamDriver) 0 }}
    - name: upstream-agent
      csi:
        driver: {{ .Values.upstreamAuthority.spire.upstreamDriver }}
        readOnly: true
    {{- end }}
    {{- with .Values.keyManager.awsKMS }}
    {{- if and (eq (.enabled | toString) "true") (or (ne .keyPolicy.policy "") (ne .keyPolicy.existingConfigMap "")) }}
    - name: aws-kms-key-policy
      configMap:
        {{- if ne .keyPolicy.policy "" }}
        name: {{ include "spire-server.fullname" . }}-aws-kms
        {{- else if ne .keyPolicy.existingConfigMap "" }}
        name: {{ .keyPolicy.existingConfigMap }}
        {{- end }}
    {{- end }}
    {{- end }}
    {{- if eq (.Values.controllerManager.enabled | toString) "true" }}
    - name: controller-manager-config
      configMap:
        name: {{ include "spire-controller-manager.fullname" . }}
    {{- end }}
    {{- if eq (.Values.tornjak.enabled | toString) "true" }}
    {{- if .Values.tornjak.config }}
    - name: {{ include "spire-tornjak.config" . }}
      configMap:
        defaultMode: 420
        name: {{ include "spire-tornjak.config" . }}
    {{- end }}
    {{- end }}
    {{- if gt (len .Values.extraVolumes) 0 }}
    {{- toYaml .Values.extraVolumes | nindent 4 }}
    {{- end }}
    {{- if eq .Values.persistence.type "emptyDir" }}
    - name: spire-data
      emptyDir: {}
    {{- else if eq .Values.persistence.type "hostPath" }}
    - name: spire-data
      hostPath:
        path: {{ .Values.persistence.hostPath }}
        type: Directory
    {{- end }}
    {{- with .Values.upstreamAuthority.vault }}
    {{- if eq (.enabled | toString) "true" }}
    {{- if ne (.insecureSkipVerify | toString) "true" }}
    {{- if eq (.caCert.type | lower) "configmap" }}
    - name: vault-ca
      configMap:
        name: {{ .caCert.name }}
    {{- else if eq (.caCert.type | lower) "secret" }}
    - name: vault-ca
      secret:
        secretName: {{ .caCert.name }}
        optional: false
    {{- end }}
    {{- end -}}
    {{- if eq (.k8sAuth.enabled | toString) "true" }}
    - name: spire-psat
      projected:
        sources:
        - serviceAccountToken:
            path: spire-server
            expirationSeconds: {{ .k8sAuth.token.expiry }}
            {{- if ne .k8sAuth.token.audience "" }}
            audience: {{ .k8sAuth.token.audience }}
            {{- end }}
    {{- end }}
    {{- end -}}
    {{- end -}}
{{ end }}