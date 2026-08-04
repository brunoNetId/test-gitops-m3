{{/*
Tenant namespace — derived from the username.
*/}}
{{- define "user-workload.namespace" -}}
{{ .Values.tenant.namespacePrefix }}{{ .Values.tenant.username }}-devspaces
{{- end }}

{{/*
Expand the name of the chart.
*/}}
{{- define "user-workload.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "user-workload.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "user-workload.labels" -}}
helm.sh/chart: {{ include "user-workload.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
ArgoCD sync-wave for Namespace
*/}}
{{- define "user-workload.namespace-syncwave" -}}
{{- if and (.Values.argocd) (.Values.argocd.syncwave) (.Values.argocd.syncwave.enabled) -}}
argocd.argoproj.io/sync-wave: "{{ .Values.argocd.syncwave.namespace }}"
{{- end }}
{{- end }}

{{/*
ArgoCD sync-wave for Kafka resources
*/}}
{{- define "user-workload.kafka-syncwave" -}}
{{- if and (.Values.argocd) (.Values.argocd.syncwave) (.Values.argocd.syncwave.enabled) -}}
argocd.argoproj.io/sync-wave: "{{ .Values.argocd.syncwave.kafka }}"
{{- end }}
{{- end }}

{{/*
ArgoCD sync-wave for Matrix resources
*/}}
{{- define "user-workload.matrix-syncwave" -}}
{{- if and (.Values.argocd) (.Values.argocd.syncwave) (.Values.argocd.syncwave.enabled) -}}
argocd.argoproj.io/sync-wave: "{{ .Values.argocd.syncwave.matrix }}"
{{- end }}
{{- end }}

{{/*
Derive room name from username — replaces "user" with "room".
*/}}
{{- define "user-workload.roomname" -}}
{{ .Values.tenant.username | replace "user" "room" }}
{{- end }}
