{{/* Nom de base */}}
{{- define "marche-cm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "marche-cm.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s" (include "marche-cm.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Labels communs */}}
{{- define "marche-cm.labels" -}}
app.kubernetes.io/name: {{ include "marche-cm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/* Selector pour un composant donné (.component) */}}
{{- define "marche-cm.selector" -}}
app.kubernetes.io/name: {{ include "marche-cm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "marche-cm.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "marche-cm.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "marche-cm.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}

{{- define "marche-cm.secretName" -}}
{{ include "marche-cm.fullname" . }}-secrets
{{- end -}}

{{- define "marche-cm.configName" -}}
{{ include "marche-cm.fullname" . }}-config
{{- end -}}

{{/*
envFrom partagé par tous les pods applicatifs : ConfigMap (non sensible) +
Secret (sensible). Hash des deux pour forcer un rollout au changement.
*/}}
{{- define "marche-cm.envFrom" -}}
- configMapRef:
    name: {{ include "marche-cm.configName" . }}
- secretRef:
    name: {{ include "marche-cm.secretName" . }}
{{- end -}}

{{/* securityContext durci, aligné sur le Dockerfile (uid 10001, non-root) */}}
{{- define "marche-cm.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 10001
runAsGroup: 10001
fsGroup: 10001
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "marche-cm.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end -}}
