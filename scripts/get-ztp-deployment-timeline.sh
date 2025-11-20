#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# Complete ZTP Deployment Timeline Tracker
# Tracks from ClusterInstance creation (if available) to TALM CGU completion
#
# Version 2.1 Features:
# 1. ClusterInstance creationTimestamp as starting point (captures SiteConfig operator reconciliation)
# 2. TALM CGU completedAt timestamp as completion point (captures accurate policy completion)
# 3. Graceful fallback for legacy deployments without ClusterInstance or TALM CGU

function usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Retrieve complete ZTP deployment timeline from GitOps sync to policy completion.

OPTIONS:
  -h, --host HOST              SSH host to connect to (bastion)
  -o, --ssh-opts "OPTS"        SSH options (e.g., "-o StrictHostKeyChecking=no")
  -c, --cluster CLUSTER_NAME   Spoke cluster name (ManagedCluster name)
  -k, --kubeconfig PATH        Path to kubeconfig on remote host
  --help                       Display this help message

VERSION 2.1 FEATURES:
  1. ClusterInstance starting point (captures SiteConfig operator reconciliation)
  2. TALM CGU completion tracking (accurate policy completion timestamp)
  3. Backward compatible with legacy deployments

TIMELINE CAPTURED:
  0. ClusterInstance creation (ENHANCED - earliest possible starting point)
  1. ManagedCluster creation (GitOps sync trigger)
  2. AgentClusterInstall lifecycle (OCP installation)
  3. ClusterDeployment progress
  4. InfraEnv and Agent registration
  5. BareMetalHost provisioning
  6. ManagedCluster import and join
  7. Policy application and compliance (PGT policies)
  8. ManifestWork deployments
  9. TALM CGU completion (ENHANCED - accurate completion timestamp)
  10. ztp-done label application

OUTPUT:
  JSON array of all deployment events with timestamps, sorted chronologically.

EXAMPLE:
  $0 -h bastion.example.com \\
     -c ci-op-vvn72slv \\
     -k /var/builds/telco-qe-preserved/ztp-hub-preserved-prod-cluster_profile_dir/hub-kubeconfig
EOF
}

# Default values
SSH_HOST=""
SSH_OPTS=""
SPOKE_CLUSTER_NAME=""
KUBECONFIG_PATH="/var/builds/telco-qe-preserved/ztp-hub-preserved-prod-cluster_profile_dir/hub-kubeconfig"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--host)
      SSH_HOST="$2"
      shift 2
      ;;
    -o|--ssh-opts)
      SSH_OPTS="$2"
      shift 2
      ;;
    -c|--cluster)
      SPOKE_CLUSTER_NAME="$2"
      shift 2
      ;;
    -k|--kubeconfig)
      KUBECONFIG_PATH="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# Validate required parameters
if [[ -z "${SSH_HOST}" ]]; then
  echo "ERROR: SSH host is required (-h/--host)" >&2
  usage >&2
  exit 1
fi

if [[ -z "${SPOKE_CLUSTER_NAME}" ]]; then
  echo "ERROR: Spoke cluster name is required (-c/--cluster)" >&2
  usage >&2
  exit 1
fi

# Build SSH command
SSH_CMD="ssh"
if [[ -n "${SSH_OPTS}" ]]; then
  SSH_CMD="${SSH_CMD} ${SSH_OPTS}"
fi
SSH_CMD="${SSH_CMD} ${SSH_HOST}"

# Function to retrieve complete ZTP deployment timeline
function get_ztp_deployment_timeline() {
  local cluster_name="$1"
  local kubeconfig="$2"

  # Remote script to execute on bastion
  ${SSH_CMD} bash -s -- "${cluster_name}" "${kubeconfig}" <<'REMOTE_SCRIPT'
#!/bin/bash
set -o errexit
set -o pipefail

CLUSTER_NAME="$1"
KUBECONFIG_PATH="$2"

export KUBECONFIG="${KUBECONFIG_PATH}"

# Collect all ZTP deployment timeline events
{
  ###############################################################################
  # MILESTONE 0: ArgoCD Application and ClusterInstance Creation
  # ArgoCD Application is the earliest starting point (universal for all ZTP)
  # ClusterInstance is SiteConfig v2 specific (captured for future use)
  ###############################################################################

  # ArgoCD Application creation (earliest GitOps trigger point)
  # Search for Application with siteconfig path (may be named differently than cluster)
  # Try common namespaces: openshift-gitops, argocd
  for ns in openshift-gitops argocd; do
    oc get applications.argoproj.io -n "${ns}" -o json 2>/dev/null | \
      jq -c --arg cluster "${CLUSTER_NAME}" '.items[] |
        select(.spec.source.path == "siteconfig") |
        {
          timestamp: .metadata.creationTimestamp,
          event: "ZTP.ArgoApplicationCreated",
          event_description: ("ArgoCD Application " + .metadata.name + " created - GitOps deployment triggered (siteconfig path)"),
          milestone: "0-GITOPS_APPLICATION",
          namespace: .metadata.namespace,
          app_name: .metadata.name
        }' 2>/dev/null | head -1 || true
  done

  # ClusterInstance creation (SiteConfig v2 operator - if available)
  # Search for any ClusterInstance in the cluster's namespace (name may differ from cluster name)
  oc get clusterinstances.siteconfig.open-cluster-management.io -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty |
    {
      timestamp: .metadata.creationTimestamp,
      event: "ZTP.ClusterInstanceCreated",
      event_description: ("ClusterInstance " + .metadata.name + " created by SiteConfig v2 operator"),
      milestone: "0-GITOPS_APPLICATION",
      clusterinstance_name: .metadata.name
    }' 2>/dev/null | head -1 || true

  # ClusterInstance conditions (may become more verbose in future)
  oc get clusterinstances.siteconfig.open-cluster-management.io -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty | .status.conditions[]? // empty |
    {
      timestamp: .lastTransitionTime,
      event: ("ClusterInstance.Condition." + .type),
      event_description: (.reason + ": " + .message),
      milestone: "0-GITOPS_APPLICATION"
    }' 2>/dev/null || true

  ###############################################################################
  # MILESTONE 1: ManagedCluster Creation (GitOps Sync Trigger)
  ###############################################################################
  oc get managedcluster "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '{
      timestamp: .metadata.creationTimestamp,
      event: "ZTP.ManagedClusterCreated",
      event_description: ("ManagedCluster created by GitOps - Start of deployment for " + .metadata.name),
      milestone: "1-GITOPS_SYNC"
    }' 2>/dev/null || true

  # ManagedCluster conditions
  oc get managedcluster "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.status.conditions[]? // empty |
    {
      timestamp: .lastTransitionTime,
      event: ("ManagedCluster.Condition." + .type),
      event_description: (.reason + ": " + .message),
      milestone: "6-IMPORT"
    }' 2>/dev/null || true

  # Check for ztp-done label
  oc get managedcluster "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c 'if .metadata.labels["ztp-done"] then
    {
      timestamp: .metadata.creationTimestamp,
      event: "ZTP.ZtpDoneLabelPresent",
      event_description: ("ztp-done label is present on cluster"),
      milestone: "10-ZTP_DONE"
    } else empty end' 2>/dev/null || true

  ###############################################################################
  # MILESTONE 2: AgentClusterInstall (OCP Installation Process)
  ###############################################################################
  # AgentClusterInstall creation
  oc get agentclusterinstall -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty |
    {
      timestamp: .metadata.creationTimestamp,
      event: "AgentClusterInstall.Created",
      event_description: ("AgentClusterInstall " + .metadata.name + " created"),
      milestone: "2-CLUSTER_INSTALL"
    }' 2>/dev/null || true

  # AgentClusterInstall conditions
  oc get agentclusterinstall -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty |
    .status.conditions[]? // empty |
    {
      timestamp: .lastTransitionTime,
      event: ("AgentClusterInstall." + .type),
      event_description: (.reason + ": " + .message),
      milestone: "2-CLUSTER_INSTALL"
    }' 2>/dev/null || true

  # AgentClusterInstall events
  oc get events -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty |
    select(.involvedObject.kind == "AgentClusterInstall") |
    {
      timestamp: (.eventTime // .lastTimestamp // .firstTimestamp),
      event: ("AgentClusterInstall." + .reason),
      event_description: .message,
      milestone: "2-CLUSTER_INSTALL"
    }' 2>/dev/null || true

  # Get detailed installation events from Assisted Service API
  EVENTS_URL=$(oc get agentclusterinstall -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -r '.items[]? // empty | .status.debugInfo.eventsURL // empty' | head -1)

  if [[ -n "${EVENTS_URL}" ]]; then
    curl -sk "${EVENTS_URL}" 2>/dev/null | \
      jq -c '.[]? // empty |
      select(.name == "cluster_status_updated") |
      {
        timestamp: .event_time,
        event: ("AssistedService.ClusterStatus." +
                (.message |
                 if contains("preparing-for-installation") then "PreparingForInstallation"
                 elif contains(" installing") then "Installing"
                 elif contains(" finalizing") then "Finalizing"
                 elif contains(" installed") then "Installed"
                 elif contains(" ready") then "Ready"
                 else "StatusUpdate" end)),
        event_description: .message,
        milestone: "2-CLUSTER_INSTALL"
      }' 2>/dev/null || true

    # Get host installation events
    curl -sk "${EVENTS_URL}" 2>/dev/null | \
      jq -c '.[]? // empty |
      select(.name == "host_status_updated" and .message | contains("installing")) |
      {
        timestamp: .event_time,
        event: "AssistedService.HostInstalling",
        event_description: .message,
        milestone: "2-CLUSTER_INSTALL"
      }' 2>/dev/null || true
  fi

  ###############################################################################
  # MILESTONE 3: ClusterDeployment
  ###############################################################################

  oc get clusterdeployment -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty |
    {
      timestamp: .metadata.creationTimestamp,
      event: "ClusterDeployment.Created",
      event_description: ("ClusterDeployment " + .metadata.name + " created"),
      milestone: "2-CLUSTER_INSTALL"
    }' 2>/dev/null || true

  oc get clusterdeployment -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty |
    .status.conditions[]? // empty |
    {
      timestamp: .lastTransitionTime,
      event: ("ClusterDeployment." + .type),
      event_description: (.reason + ": " + .message),
      milestone: "2-CLUSTER_INSTALL"
    }' 2>/dev/null || true

  ###############################################################################
  # MILESTONE 4: InfraEnv and Agent Registration
  ###############################################################################

  oc get infraenv -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty |
    {
      timestamp: .metadata.creationTimestamp,
      event: "InfraEnv.Created",
      event_description: ("InfraEnv " + .metadata.name + " created for discovery ISO"),
      milestone: "3-DISCOVERY"
    }' 2>/dev/null || true

  oc get infraenv -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty |
    .status.conditions[]? // empty |
    {
      timestamp: .lastTransitionTime,
      event: ("InfraEnv." + .type),
      event_description: (.reason + ": " + .message),
      milestone: "3-DISCOVERY"
    }' 2>/dev/null || true

  # Agent registration
  oc get agent -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty |
    {
      timestamp: .metadata.creationTimestamp,
      event: "Agent.Registered",
      event_description: ("Agent " + .metadata.name + " registered with discovery service"),
      milestone: "3-DISCOVERY"
    }' 2>/dev/null || true

  oc get agent -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty |
    .status.conditions[]? // empty |
    {
      timestamp: .lastTransitionTime,
      event: ("Agent." + .type),
      event_description: (.reason + ": " + .message),
      milestone: "3-DISCOVERY"
    }' 2>/dev/null || true

  ###############################################################################
  # MILESTONE 5: BareMetalHost Provisioning
  ###############################################################################

  oc get baremetalhost -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty |
    {
      timestamp: .metadata.creationTimestamp,
      event: "BareMetalHost.Created",
      event_description: ("BareMetalHost " + .metadata.name + " created"),
      milestone: "4-PROVISIONING"
    }' 2>/dev/null || true

  oc get events -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty |
    select(.involvedObject.kind == "BareMetalHost") |
    {
      timestamp: (.eventTime // .lastTimestamp // .firstTimestamp),
      event: ("BareMetalHost." + .reason),
      event_description: (.involvedObject.name + ": " + .message),
      milestone: "4-PROVISIONING"
    }' 2>/dev/null || true

  ###############################################################################
  # MILESTONE 6: ManagedCluster Import Events
  ###############################################################################

  oc get events -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty |
    select(.involvedObject.kind == "ManagedCluster") |
    {
      timestamp: (.eventTime // .lastTimestamp // .firstTimestamp),
      event: ("ManagedCluster." + .reason),
      event_description: .message,
      milestone: "6-IMPORT"
    }' 2>/dev/null || true

  ###############################################################################
  # MILESTONE 7: ManifestWork Application
  ###############################################################################

  oc get manifestwork -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty |
    {
      timestamp: .metadata.creationTimestamp,
      event: ("ManifestWork.Created." + .metadata.name),
      event_description: ("ManifestWork " + .metadata.name + " created"),
      milestone: "7-MANIFESTWORK"
    }' 2>/dev/null || true

  oc get manifestwork -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty |
    {
      name: .metadata.name,
      conditions: .status.conditions
    } |
    .conditions[]? // empty |
    {
      timestamp: .lastTransitionTime,
      event: ("ManifestWork." + input.name + "." + .type),
      event_description: (.reason + ": " + .message),
      milestone: "7-MANIFESTWORK"
    }' 2>/dev/null || true

  ###############################################################################
  # MILESTONE 8: Policy Application and Compliance (PGT Policies)
  ###############################################################################

  # Get all policy status changes (not just compliant)
  oc get events -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty |
    select(.involvedObject.kind == "Policy") |
    select(.reason == "PolicyStatusSync") |
    {
      timestamp: (.eventTime // .lastTimestamp // .firstTimestamp),
      event: ("Policy." + (.involvedObject.name | split(".")[1]) + "." +
              (if .message | contains("Compliant") then
                if .message | contains("NonCompliant") then "NonCompliant"
                else "Compliant" end
              else "StatusChange" end)),
      event_description: .message,
      milestone: "8-POLICY"
    }' 2>/dev/null || true

  # Check current policy status
  oc get policy -n "${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -c '.items[]? // empty |
    {
      timestamp: (.status.status[]? // empty |
                  select(.compliant == "Compliant") |
                  .lastTransition // .metadata.creationTimestamp),
      event: ("Policy." + .metadata.name),
      event_description: ("Policy " + .metadata.name + " status: " +
                         (.status.status[]?.compliant // "Unknown")),
      milestone: "8-POLICY"
    }' 2>/dev/null || true

  ###############################################################################
  # MILESTONE 9: TALM CGU Completion (Version 2.1)
  # Query the ClusterGroupUpgrade resource in ztp-install namespace
  # Provides accurate completion timestamp when TALM recognizes all policies compliant
  ###############################################################################

  # Look for CGU named after the cluster in ztp-install namespace
  oc get clustergroupupgrade "${CLUSTER_NAME}" -n ztp-install -o json 2>/dev/null | \
    jq -c 'if .status.status.completedAt then {
      timestamp: .status.status.completedAt,
      event: "TALM.CGU.Completed",
      event_description: ("TALM ClusterGroupUpgrade " + .metadata.name + " completed - All policies applied and cluster ready"),
      milestone: "9-TALM_CGU_COMPLETION",
      cgu_name: .metadata.name,
      cgu_namespace: .metadata.namespace
    } else empty end' 2>/dev/null || true

  # CGU status and conditions
  oc get clustergroupupgrade "${CLUSTER_NAME}" -n ztp-install -o json 2>/dev/null | \
    jq -c '.status.conditions[]? // empty |
    {
      timestamp: .lastTransitionTime,
      event: ("TALM.CGU.Condition." + .type),
      event_description: (.reason + ": " + .message),
      milestone: "9-TALM_CGU_COMPLETION",
      cgu_status: .status
    }' 2>/dev/null || true

  # CGU managed policies status
  oc get clustergroupupgrade "${CLUSTER_NAME}" -n ztp-install -o json 2>/dev/null | \
    jq -c '.status.managedPoliciesForUpgrade[]? // empty |
    {
      timestamp: (.status.completedAt // .lastTransitionTime // now | todate),
      event: ("TALM.CGU.ManagedPolicy." + .name),
      event_description: ("Managed policy " + .name + " - " + (.status.compliant // "unknown")),
      milestone: "9-TALM_CGU_COMPLETION"
    }' 2>/dev/null || true

  ###############################################################################
  # MILESTONE 10: ZTP Done Label (if applied via event)
  ###############################################################################

  # This would require event tracking for label changes
  # We already checked the current state above

} | jq -s 'map(select(.timestamp != null)) | sort_by(.timestamp)'

REMOTE_SCRIPT
}

# Execute the function
get_ztp_deployment_timeline "${SPOKE_CLUSTER_NAME}" "${KUBECONFIG_PATH}"

