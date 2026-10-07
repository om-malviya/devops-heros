{{/* Chart name */}}
{{- define "taskboard.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fully qualified name: <release>-taskboard unless overridden */}}
{{- define "taskboard.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "taskboard.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Common labels */}}
{{- define "taskboard.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "taskboard.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: taskboard
{{- end -}}

{{/* Selector labels for a component: include "taskboard.selectorLabels" (dict "root" . "component" "backend") */}}
{{- define "taskboard.selectorLabels" -}}
app: {{ include "taskboard.fullname" .root }}-{{ .component }}
app.kubernetes.io/name: {{ include "taskboard.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/* Image tag defaults to appVersion */}}
{{- define "taskboard.backendImage" -}}
{{ .Values.backend.image.repository }}:{{ .Values.backend.image.tag | default .Chart.AppVersion }}
{{- end -}}
{{- define "taskboard.frontendImage" -}}
{{ .Values.frontend.image.repository }}:{{ .Values.frontend.image.tag | default .Chart.AppVersion }}
{{- end -}}

{{/* Secret name holding DB credentials */}}
{{- define "taskboard.secretName" -}}
{{- if .Values.postgres.existingSecret -}}
{{ .Values.postgres.existingSecret }}
{{- else -}}
{{ include "taskboard.fullname" . }}-secrets
{{- end -}}
{{- end -}}

{{/* Database URL rendered into the chart-managed Secret */}}
{{- define "taskboard.databaseUrl" -}}
{{- if .Values.postgres.enabled -}}
postgresql+psycopg://{{ .Values.postgres.username }}:{{ .Values.postgres.password }}@{{ include "taskboard.fullname" . }}-postgres:5432/{{ .Values.postgres.database }}
{{- else -}}
{{ required "externalDatabaseUrl is required when postgres.enabled=false" .Values.externalDatabaseUrl }}
{{- end -}}
{{- end -}}
