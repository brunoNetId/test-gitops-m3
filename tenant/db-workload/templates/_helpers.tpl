{{/*
Tenant namespace — derived from the username.
*/}}
{{- define "db-workload.namespace" -}}
{{ .Values.tenant.namespacePrefix }}{{ .Values.tenant.username }}-devspaces
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "db-workload.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "db-workload.labels" -}}
helm.sh/chart: {{ include "db-workload.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
