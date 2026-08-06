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
NAMESPACE_PREFIX="m3-"
LABEL_KEY="app.kubernetes.io/part-of"
LABEL_VALUE="tenant-m3"
LABEL_SELECTOR="${LABEL_KEY}=${LABEL_VALUE}"

CRED_SECRET_NS="showroom"
CRED_SECRET_NAME="im-credentials"
CRED_SECRET_KEY="openshift.json"

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

# Load OpenShift credentials
echo "Loading OpenShift credentials..."
ESCAPED_KEY=$(echo "$CRED_SECRET_KEY" | sed 's/\./\\./g')
CRED_JSON=$(oc get secret "$CRED_SECRET_NAME" -n "$CRED_SECRET_NS" \
  -o jsonpath="{.data.${ESCAPED_KEY}}" | base64 -d)
AVAILABLE_USERS=$(echo "$CRED_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
echo "Found ${AVAILABLE_USERS} users in credentials Secret."

# Load NooBaa S3 credentials
echo "Loading NooBaa S3 credentials..."
S3_ACCESS_KEY=$(oc get secret "$NOOBAA_SECRET_NAME" -n "$NOOBAA_SECRET_NS" \
  -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
S3_SECRET_KEY=$(oc get secret "$NOOBAA_SECRET_NAME" -n "$NOOBAA_SECRET_NS" \
  -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
S3_ENDPOINT="https://$(oc get route s3 -n "$NOOBAA_SECRET_NS" -o jsonpath='{.spec.host}')"
echo "S3 endpoint: ${S3_ENDPOINT}"

if [ "$COUNT" -gt "$AVAILABLE_USERS" ]; then
  echo "ERROR: Requested ${COUNT} tenants but only ${AVAILABLE_USERS} users available."
  exit 1
fi

generate_id() {
  LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 5 || true
}

for i in $(seq 1 "$COUNT"); do
  OC_USER="user${i}"
  PASSWORD=$(echo "$CRED_JSON" | python3 -c "
import sys, json
users = json.load(sys.stdin)
match = next((u['password'] for u in users if u['name'] == '${OC_USER}'), None)
if match:
    print(match)
else:
    sys.exit(1)
")

  if $RANDOM_ID; then
    USERNAME="user-$(generate_id)"
  else
    USERNAME="$OC_USER"
  fi

  NAMESPACE="${NAMESPACE_PREFIX}${USERNAME}-devspaces"
  APP_NAME="tenant-${USERNAME}-m3"

  echo "Creating tenant for ${USERNAME} (openshift user: ${OC_USER}, namespace: ${NAMESPACE})..."

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
  source:
    path: tenant/user-workload
    repoURL: ${REPO_URL}
    targetRevision: ${TARGET_REVISION}
    helm:
      valuesObject:
        tenant:
          username: ${USERNAME}
          password: "${PASSWORD}"
          openshiftUser: ${OC_USER}
          namespacePrefix: "${NAMESPACE_PREFIX}"
        s3:
          endpoint: "${S3_ENDPOINT}"
          accessKey: "${S3_ACCESS_KEY}"
          secretKey: "${S3_SECRET_KEY}"
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
