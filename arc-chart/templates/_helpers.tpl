{{- define "arc-runner.cargoCachePath" -}}
{{- if .Values.cargoCachePath -}}
{{ .Values.cargoCachePath }}
{{- else -}}
/tmp/cargo-cache
{{- end -}}
{{- end -}}
