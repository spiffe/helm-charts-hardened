{
  "type": {{ toJson .Type }},
  "keyId": {{ toJson .AuthorizationCrt.Subject.CommonName }},
  "principals": [{{ toJson .AuthorizationCrt.Subject.CommonName }}],
  "extensions": {{ toJson .Extensions }},
  "criticalOptions": {{ toJson .CriticalOptions }}
}
