{{- if eq (len .AuthorizationCrt.URIs) 1 }}
{{-   $san := printf "%s" (index .AuthorizationCrt.URIs 0) }}
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
