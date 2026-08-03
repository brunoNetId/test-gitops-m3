# OCP Dev Days Roadshow - GitOps (Module 3)

Helm charts and ArgoCD manifests for the App Connect AI workshop (module 3 of the OCP Dev Days Roadshow).

## Architecture Overview

This module uses the same GitOps patterns as module 1 (`ocp-dev-days-rdshw-gitops`): Helm charts deployed via ArgoCD using the app-of-apps pattern. Each participant gets isolated resources in their own namespace.

### Cluster-Level Components

Deployed once via the **app-of-apps** pattern (`cluster/app-of-apps/`):

| Component | Chart Path | Description |
|-----------|-----------|-------------|
| AMQ Streams (Kafka instance) | `cluster/amq-streams/kafka-instance/` | Per-user Kafka cluster (KRaft mode) |

### Tenant Provisioning

<!-- Per-user provisioning will be added here as we build the tenant charts -->

## References

- **Ansible source (requirements):** [`ocp4-workload-app-connect-ai`](https://github.com/redhat-cop/agnosticd/tree/development/ansible/roles_ocp_workloads/ocp4-workload-app-connect-ai)
- **GitOps reference (module 1):** [`ocp-dev-days-rdshw-gitops`](https://github.com/rhpds/ocp-dev-days-rdshw-gitops)
- **Deployment differences:** See `deployment-differences.md` in the workspace root
