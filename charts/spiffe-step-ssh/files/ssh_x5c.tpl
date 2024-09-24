{{- define "walkListFindURLSANs" }}
{{-   $typeSlice := slice .chunk 0 1 }}
{{-   $sizeSlice := (slice .chunk 1 2) }}
{{-   if and (ne $typeSlice nil) (ne $sizeSlice nil) }}
{{-     $type := index $typeSlice 0 | int }}
{{-     $size := index $sizeSlice 0 | int }}
{{-     $newStart := (add 2 $size) }}
{{-     $chunk := slice .chunk 2 $newStart }}
{{-     if eq $type 134 }}
{{-       $_ := set .root "retval" (append .root.retval (printf "%s" $chunk)) }}
{{-     else }}
{{-       $nextChunk := slice .chunk $newStart }}
{{-       if ne $nextChunk nil }}
{{-         $args := dict "root" .root "chunk" $nextChunk }}
{{-         template "walkListFindURLSANs" $args }}
{{-       end }}
{{-     end }}
{{-   end }}
{{- end }}
{{- define "findURLSANs" }}
{{-   $root := . }}
{{-   $ext := .ext }}
{{-   range $ext }}
{{-     if eq (printf "%s" .Id) "2.5.29.17" }}
{{-       $t := index (slice .Value 0 1) 0 | int }}
{{-       if eq $t 48 }}
{{-         $args := dict "root" $root "chunk" (slice .Value 2) }}
{{-         template "walkListFindURLSANs" $args }}
{{-       end }}
{{-     end }}
{{-   end }}
{{- end }}
{{- $prepURLSANs := dict "retval" (list) "ext" .AuthorizationCrt.Extensions }}
{{- template "findURLSANs" $prepURLSANs }}
{{- if eq (len $prepURLSANs.retval) 1 }}
{{-   $san := $prepURLSANs.retval | join "" }}
{{-   if hasPrefix "spiffe://@TRUST_DOMAIN@/@PREFIX@/" $san }}
{{-     $name := trimPrefix "spiffe://@TRUST_DOMAIN@/@PREFIX@/" $san }}
{
  "type": {{ toJson .Type }},
  "keyId": {{ toJson $name }},
  "principals": [{{ toJson $name }}],
  "extensions": {{ toJson .Extensions }},
  "criticalOptions": {{ toJson .CriticalOptions }}
}
{{-   end }}
{{- end }}
