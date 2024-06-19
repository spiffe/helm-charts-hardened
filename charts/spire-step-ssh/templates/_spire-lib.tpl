{{- define "spire-lib.kubectl-image" }}
{{- $root := deepCopy . }}
{{- $tag := $root.image.tag | toString }}
{{- if eq (len $tag) 0 }}
{{- $_ := set $root.image "tag" (regexReplaceAll "^(v?\\d+\\.\\d+\\.\\d+).*" $root.KubeVersion "${1}") }}
{{- end }}
{{- include "spire-lib.image" $root }}
{{- end }}

{{- define "spire-lib.registry" }}
{{- if ne (len (dig "spire" "image" "registry" "" .global)) 0 }}
{{- print .global.spire.image.registry "/"}}
{{- else if ne (len (.image.registry)) 0 }}
{{- print .image.registry "/"}}
{{- end }}
{{- end }}

{{- define "spire-lib.image" -}}
{{- $registry := include "spire-lib.registry" . }}
{{- $repo := .image.repository }}
{{- $tag := (default .image.tag .image.version) | toString }}
{{- if eq (substr 0 7 $tag) "sha256:" }}
{{- printf "%s/%s@%s" $registry $repo $tag }}
{{- else if .appVersion }}
{{- $appVersion := .appVersion }}
{{- if and (hasKey . "ubi") (dig "openshift" false .global) }}
{{- $appVersion = printf "ubi-%s" $appVersion }}
{{- end }}
{{- printf "%s%s:%s" $registry $repo (default $appVersion $tag) }}
{{- else if $tag }}
{{- printf "%s%s:%s" $registry $repo $tag }}
{{- else }}
{{- printf "%s%s" $registry $repo }}
{{- end }}
{{- end }}
