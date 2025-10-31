{{- define "arc-runner-windows.cargoCachePath" -}}
{{- if .Values.cargoCachePath -}}
{{ .Values.cargoCachePath }}
{{- else -}}
C:\cargo-cache
{{- end -}}
{{- end -}}
