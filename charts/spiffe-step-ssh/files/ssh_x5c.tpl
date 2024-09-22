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
{{-   $ext := .ext }}
{{-   $rawSANs := printf "%s" (index $ext 5).Value }}
{{-   $t := printf "%.1s" $rawSANs }}
{{-   $seq := ("ME==" | b64dec) }}
{{-   if eq $t $seq }}
{{-     $args := dict "root" . "chunk" (slice (index $ext 5).Value 2) }}
{{-     template "walkListFindURLSANs" $args }}
{{-   end }}
{{- end }}
{{- $prepURLSANs := dict "retval" (list) "ext" .AuthorizationCrt.Extensions }}
{{- template "findURLSANs" $prepURLSANs }}
{{- if eq (len $prepURLSANs.retval) 1 }}
{{-   $san := $prepURLSANs.retval | join "" }}
{{-   if hasPrefix "spiffe://example.org/sshd/" $san }}
{{-     $name := trimPrefix "spiffe://example.org/sshd/" $san }}
{
  "type": {{ toJson .Type }},
  "keyId": {{ toJson $name }},
  "principals": [{{ toJson $name }}],
  "extensions": {{ toJson .Extensions }},
  "criticalOptions": {{ toJson .CriticalOptions }}
}
{{-   end }}
{{- end }}
