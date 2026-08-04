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
LABEL_KEY="app.kubernetes.io/part-of"
LABEL_VALUE="tenant-m3"
LABEL_SELECTOR="${LABEL_KEY}=${LABEL_VALUE}"

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
    echo "  Removing finalizers and deleting $APP..."
    oc patch "$APP" -n "$ARGOCD_NS" --type merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
    oc delete "$APP" -n "$ARGOCD_NS" 2>/dev/null || true
  done
  echo "Done."
  exit 0
fi

generate_id() {
  cat /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c 5
}

for i in $(seq 1 "$COUNT"); do
  if $RANDOM_ID; then
    USERNAME="user-$(generate_id)"
  else
    USERNAME="user${i}"
  fi

  NAMESPACE="${USERNAME}-devspaces"
  APP_NAME="tenant-${USERNAME}-m3"

  echo "Creating tenant for ${USERNAME} (namespace: ${NAMESPACE})..."

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
