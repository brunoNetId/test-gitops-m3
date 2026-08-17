#!/bin/bash
#
# Creates (or deletes) per-user ArgoCD Applications for tenant testing.
#
# Usage:
#   ./bootstrap/create-tenants.sh --count 3                  # user1, user2, user3
#   ./bootstrap/create-tenants.sh --count 3 --random-id      # user-a7x2b, user-k9m4c, ...
#   ./bootstrap/create-tenants.sh --delete                   # removes all tenant apps
#

set -euo pipefail

REPO_URL="https://github.com/brunoNetId/test-gitops-m3.git"
TARGET_REVISION="main"
ARGOCD_NS="openshift-gitops"
NAMESPACE_PREFIX=""
LABEL_KEY="app.kubernetes.io/part-of"
LABEL_VALUE="tenant-m3"
LABEL_SELECTOR="${LABEL_KEY}=${LABEL_VALUE}"

PARENT_APP="app-of-apps"

NOOBAA_SECRET_NS="openshift-storage"
NOOBAA_SECRET_NAME="noobaa-admin"

COUNT=1
RANDOM_ID=false
DELETE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --count)    COUNT="$2"; shift 2 ;;
    --random-id) RANDOM_ID=true; shift ;;
    --delete)   DELETE=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if $DELETE; then
  echo "Deleting all tenant Applications..."
  APPS=$(oc get applications -n "$ARGOCD_NS" -l "$LABEL_SELECTOR" -o name 2>/dev/null || true)
  if [ -z "$APPS" ]; then
    echo "No tenant Applications found."
    exit 0
  fi
  for APP in $APPS; do
    echo "  Deleting $APP..."
    oc delete "$APP" -n "$ARGOCD_NS" 2>/dev/null || true
  done
  echo "Done."
  exit 0
fi

# Load values from parent app-of-apps
echo "Loading values from parent app-of-apps..."
PARENT_VALUES=$(oc get application "$PARENT_APP" -n "$ARGOCD_NS" \
  -o jsonpath='{.spec.source.helm.valuesObject}')
ANSIBLE_INPUT_PASSWORD=$(echo "$PARENT_VALUES" | python3 -c "import sys,json; print(json.load(sys.stdin)['common']['password'])")
ANSIBLE_INPUT_MAAS_KEY=$(echo "$PARENT_VALUES" | python3 -c "import sys,json; print(json.load(sys.stdin)['vault']['secrets']['litellm']['apiKey'])")
ANSIBLE_INPUT_MAAS_URL=$(echo "$PARENT_VALUES" | python3 -c "import sys,json; print(json.load(sys.stdin)['vault']['secrets']['litellm']['apiUrl'])")
ANSIBLE_INPUT_MAAS_HOST=$(echo "$ANSIBLE_INPUT_MAAS_URL" | sed 's|https://||; s|/v1||')
echo "  Password: (loaded)"
echo "  MaaS URL: ${ANSIBLE_INPUT_MAAS_URL}"
echo "  MaaS host: ${ANSIBLE_INPUT_MAAS_HOST}"

# Load NooBaa S3 credentials
echo "Loading NooBaa S3 credentials..."
ANSIBLE_INPUT_S3_ACCESS_KEY=$(oc get secret "$NOOBAA_SECRET_NAME" -n "$NOOBAA_SECRET_NS" \
  -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
ANSIBLE_INPUT_S3_SECRET_KEY=$(oc get secret "$NOOBAA_SECRET_NAME" -n "$NOOBAA_SECRET_NS" \
  -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
ANSIBLE_INPUT_S3_ENDPOINT="https://$(oc get route s3 -n "$NOOBAA_SECRET_NS" -o jsonpath='{.spec.host}')"
echo "S3 endpoint: ${ANSIBLE_INPUT_S3_ENDPOINT}"

# Detect cluster apps domain
ANSIBLE_INPUT_APPS_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
echo "Apps domain: ${ANSIBLE_INPUT_APPS_DOMAIN}"

generate_api_key() {
  local tier="$1" user="$2"
  echo "${tier}-${user}-$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 12 || true)"
}

generate_id() {
  LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 5 || true
}

for i in $(seq 1 "$COUNT"); do
  ANSIBLE_INPUT_USERNAME="user${i}"

  if $RANDOM_ID; then
    USERNAME="user-$(generate_id)"
  else
    USERNAME="$ANSIBLE_INPUT_USERNAME"
  fi

  NAMESPACE="${NAMESPACE_PREFIX}${USERNAME}-devspaces"
  APP_NAME="tenant-${USERNAME}-m3"

  SILVER_API_KEY=$(generate_api_key "silver" "$USERNAME")
  GOLD_API_KEY=$(generate_api_key "gold" "$USERNAME")

  echo "Creating tenant for ${USERNAME} (openshift user: ${ANSIBLE_INPUT_USERNAME}, namespace: ${NAMESPACE})..."

  cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${APP_NAME}
  namespace: ${ARGOCD_NS}
  labels:
    ${LABEL_KEY}: ${LABEL_VALUE}
  finalizers:
    - resources-finalizer.argocd.argoproj.io/foreground
spec:
  destination:
    namespace: ${NAMESPACE}
    server: https://kubernetes.default.svc
  project: default
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
    - group: workspace.devfile.io
      kind: DevWorkspace
      jsonPointers:
        - /spec
  source:
    path: tenant/user-workload
    repoURL: ${REPO_URL}
    targetRevision: ${TARGET_REVISION}
    helm:
      valuesObject:
        tenant:
          username: ${USERNAME}
          password: "${ANSIBLE_INPUT_PASSWORD}"
          openshiftUser: ${ANSIBLE_INPUT_USERNAME}
          namespacePrefix: "${NAMESPACE_PREFIX}"
        cluster:
          appsDomain: "${ANSIBLE_INPUT_APPS_DOMAIN}"
        s3:
          endpoint: "${ANSIBLE_INPUT_S3_ENDPOINT}"
          accessKey: "${ANSIBLE_INPUT_S3_ACCESS_KEY}"
          secretKey: "${ANSIBLE_INPUT_S3_SECRET_KEY}"
        connectivityLink:
          maasUrl: "${ANSIBLE_INPUT_MAAS_URL}"
          maasKey: "${ANSIBLE_INPUT_MAAS_KEY}"
          silverApiKey: "${SILVER_API_KEY}"
          goldApiKey: "${GOLD_API_KEY}"
          llmApi:
            host: "${ANSIBLE_INPUT_MAAS_HOST}"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    retry:
      limit: 30
      backoff:
        duration: 10s
        factor: 1
        maxDuration: 10s
    syncOptions:
      - CreateNamespace=false
      - RespectIgnoreDifferences=true
      - SkipDryRunOnMissingResource=true
EOF

  echo "  Created Application: ${APP_NAME}"
done

echo "Done. Created ${COUNT} tenant(s)."
