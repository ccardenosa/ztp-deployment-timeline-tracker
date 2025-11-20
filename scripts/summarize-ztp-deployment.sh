#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# ZTP Deployment Timeline Summary - ENHANCED VERSION
# Generates human-readable summary from ClusterInstance to TALM CGU completion
#
# ENHANCEMENTS (Ian Miller feedback):
# 1. Use ClusterInstance creationTimestamp as starting point
# 2. Use TALM CGU completedAt timestamp as completion point

function usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Generate a summary of ZTP deployment timeline with key milestones.
ENHANCED version with ClusterInstance starting point and TALM CGU completion.

OPTIONS:
  -h, --host HOST              SSH host to connect to (bastion)
  -o, --ssh-opts "OPTS"        SSH options
  -c, --cluster CLUSTER_NAME   Spoke cluster name
  -k, --kubeconfig PATH        Path to kubeconfig on remote host
  --json                       Output in JSON format
  --help                       Display this help message

ENHANCEMENTS:
  - ClusterInstance as true starting point (captures SiteConfig operator time)
  - TALM CGU completion as true ending point (captures when TALM completes work)

EXAMPLE:
  $0 -h bastion.example.com -c my-cluster
EOF
}

# Default values
SSH_HOST=""
SSH_OPTS=""
SPOKE_CLUSTER_NAME=""
KUBECONFIG_PATH="/var/builds/telco-qe-preserved/ztp-hub-preserved-prod-cluster_profile_dir/hub-kubeconfig"
JSON_OUTPUT=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--host) SSH_HOST="$2"; shift 2 ;;
    -o|--ssh-opts) SSH_OPTS="$2"; shift 2 ;;
    -c|--cluster) SPOKE_CLUSTER_NAME="$2"; shift 2 ;;
    -k|--kubeconfig) KUBECONFIG_PATH="$2"; shift 2 ;;
    --json) JSON_OUTPUT=true; shift ;;
    --help) usage; exit 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# Validate
if [[ -z "${SSH_HOST}" ]] || [[ -z "${SPOKE_CLUSTER_NAME}" ]]; then
  echo "ERROR: SSH host and cluster name are required" >&2
  usage >&2
  exit 1
fi

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get full timeline
TIMELINE_DATA=$("${SCRIPT_DIR}/get-ztp-deployment-timeline.sh" \
  --host "${SSH_HOST}" \
  ${SSH_OPTS:+--ssh-opts "${SSH_OPTS}"} \
  --cluster "${SPOKE_CLUSTER_NAME}" \
  --kubeconfig "${KUBECONFIG_PATH}" 2>/dev/null)

if ${JSON_OUTPUT}; then
  # JSON output with milestone summary
  echo "${TIMELINE_DATA}" | jq '{
    cluster: "'${SPOKE_CLUSTER_NAME}'",
    version: "2.1",
    features: ["ClusterInstance starting point", "TALM CGU completion"],
    total_events: (. | length),
    milestones: (group_by(.milestone) | map({
      milestone: .[0].milestone,
      event_count: (. | length),
      first_event: (.[0] | {timestamp, event, event_description}),
      last_event: (.[-1] | {timestamp, event, event_description})
    })),
    key_timestamps: {
      clusterinstance_created: ([.[] | select(.event == "ZTP.ClusterInstanceCreated")][0].timestamp // null),
      gitops_sync: ([.[] | select(.event == "ZTP.ManagedClusterCreated")][0].timestamp // null),
      cluster_install_start: ([.[] | select(.event == "AgentClusterInstall.Created")][0].timestamp // null),
      discovery_iso_ready: ([.[] | select(.event == "InfraEnv.ImageCreated")][0].timestamp // null),
      agent_registered: ([.[] | select(.event == "Agent.Registered")][0].timestamp // null),
      install_started: ([.[] | select(.event | contains("InstallationInProgress"))][0].timestamp // null),
      install_completed: ([.[] | select(.event | contains("Completed") or contains("Installed"))][0].timestamp // null),
      import_started: ([.[] | select(.event == "ManagedCluster.Importing")][0].timestamp // null),
      cluster_available: ([.[] | select(.event == "ManagedCluster.Condition.ManagedClusterConditionAvailable")][0].timestamp // null),
      policies_compliant: ([.[] | select(.event | contains("Policy") and contains("Compliant") and (.event | contains("NonCompliant") | not))][-1].timestamp // null),
      talm_cgu_completed: ([.[] | select(.event == "TALM.CGU.Completed")][0].timestamp // null),
      ztp_done: ([.[] | select(.event == "ZTP.ZtpDoneLabelPresent")][0].timestamp // null)
    },
    all_events: .
  }'
else
  # Build SSH command
  ssh_cmd="ssh"
  if [[ -n "${SSH_OPTS}" ]]; then
    ssh_cmd="${ssh_cmd} ${SSH_OPTS}"
  fi
  ssh_cmd="${ssh_cmd} ${SSH_HOST}"

  # Get hub cluster name from the infrastructure resource
  HUB_CLUSTER_NAME=$(${ssh_cmd} "oc --kubeconfig ${KUBECONFIG_PATH} get infrastructure cluster -o jsonpath='{.status.infrastructureName}' 2>/dev/null" || echo "Unknown")

  # Check if ztp-done label is present
  ZTP_DONE_STATUS=$(echo "${TIMELINE_DATA}" | jq -r 'if ([.[] | select(.event? == "ZTP.ZtpDoneLabelPresent")] | length) > 0 then "Present" else "Not Present" end')

  # Check if TALM CGU completion is present
  TALM_CGU_STATUS=$(echo "${TIMELINE_DATA}" | jq -r 'if ([.[] | select(.event? == "TALM.CGU.Completed")] | length) > 0 then "Present" else "Not Present" end')

  # Check if ArgoCD Application and ClusterInstance are present
  ARGO_APP_STATUS=$(echo "${TIMELINE_DATA}" | jq -r 'if ([.[] | select(.event? == "ZTP.ArgoApplicationCreated")] | length) > 0 then "Present" else "Not Present" end')
  CLUSTERINSTANCE_STATUS=$(echo "${TIMELINE_DATA}" | jq -r 'if ([.[] | select(.event? == "ZTP.ClusterInstanceCreated")] | length) > 0 then "Present" else "Not Present" end')

  # Human-readable output
  echo "======================================================================"
  echo "ZTP Deployment Timeline Summary"
  echo "======================================================================"
  echo "Hub Cluster: ${HUB_CLUSTER_NAME}"
  echo "Bastion Host: ${SSH_HOST}"
  echo "Spoke Cluster: ${SPOKE_CLUSTER_NAME}"
  echo ""
  echo "Deployment Features:"
  echo "  - ArgoCD Application Starting Point: ${ARGO_APP_STATUS}"
  echo "  - ClusterInstance Tracking: ${CLUSTERINSTANCE_STATUS}"
  echo "  - TALM CGU Completion: ${TALM_CGU_STATUS}"
  echo "  - ztp-done Label: ${ZTP_DONE_STATUS}"
  echo ""
  echo "Total Events Captured: $(echo "${TIMELINE_DATA}" | jq '. | length')"
  echo ""

  echo "======================================================================"
  echo "KEY MILESTONES"
  echo "======================================================================"

  # Extract key timestamps (with ArgoCD Application, ClusterInstance, and TALM CGU)
  ARGO_APP=$(echo "${TIMELINE_DATA}" | jq -r '([.[] | select(.event? == "ZTP.ArgoApplicationCreated")] | if length > 0 then .[0].timestamp else "N/A" end)')
  CLUSTERINSTANCE=$(echo "${TIMELINE_DATA}" | jq -r '([.[] | select(.event? == "ZTP.ClusterInstanceCreated")] | if length > 0 then .[0].timestamp else "N/A" end)')
  GITOPS_SYNC=$(echo "${TIMELINE_DATA}" | jq -r '([.[] | select(.event? == "ZTP.ManagedClusterCreated")] | if length > 0 then .[0].timestamp else "N/A" end)')
  ACI_CREATED=$(echo "${TIMELINE_DATA}" | jq -r '([.[] | select(.event? == "AgentClusterInstall.Created")] | if length > 0 then .[0].timestamp else "N/A" end)')
  ISO_READY=$(echo "${TIMELINE_DATA}" | jq -r '([.[] | select(.event? == "InfraEnv.ImageCreated")] | if length > 0 then .[0].timestamp else "N/A" end)')
  AGENT_REG=$(echo "${TIMELINE_DATA}" | jq -r '([.[] | select(.event? == "Agent.Registered")] | if length > 0 then .[0].timestamp else "N/A" end)')
  AGENT_BOUND=$(echo "${TIMELINE_DATA}" | jq -r '([.[] | select(.event? == "Agent.Bound")] | if length > 0 then .[0].timestamp else "N/A" end)')
  INSTALL_START=$(echo "${TIMELINE_DATA}" | jq -r '([.[] | select(.event? == "AssistedService.ClusterStatus.Installing" or (.event? | test("InstallationInProgress")))] | if length > 0 then .[0].timestamp else "N/A" end)')
  INSTALL_COMPLETE=$(echo "${TIMELINE_DATA}" | jq -r '([.[] | select(.event? == "AssistedService.ClusterStatus.Installed" or .event? == "Agent.Installed" or (.event? | test("InstallationCompleted|Installed")))] | if length > 0 then .[0].timestamp else "N/A" end)')
  # Import starts when klusterlet ManifestWork is created (ACM agent deployment)
  IMPORT_START=$(echo "${TIMELINE_DATA}" | jq -r '([.[] | select(.event? | test("ManifestWork.*klusterlet"))] | if length > 0 then .[0].timestamp else "N/A" end)')
  CLUSTER_AVAIL=$(echo "${TIMELINE_DATA}" | jq -r '([.[] | select(.event? == "ManagedCluster.Condition.ManagedClusterConditionAvailable")] | if length > 0 then .[0].timestamp else "N/A" end)')
  POLICIES_DONE=$(echo "${TIMELINE_DATA}" | jq -r '([.[] | select(.event? | test("Policy.*Compliant") and (test("NonCompliant") | not))] | if length > 0 then .[-1].timestamp else "N/A" end)')
  TALM_CGU_DONE=$(echo "${TIMELINE_DATA}" | jq -r '([.[] | select(.event? == "TALM.CGU.Completed")] | if length > 0 then .[0].timestamp else "N/A" end)')

  # Function to calculate duration in human-readable format
  format_duration() {
    local seconds=$1
    if [[ $seconds -lt 0 ]]; then
      echo "N/A"
      return
    fi

    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    local result=""
    [[ $days -gt 0 ]] && result="${days}d"
    if [[ $hours -gt 0 ]]; then
      result="${result}${hours}h$(printf "%02d" ${minutes})m$(printf "%02d" ${secs})s"
    elif [[ $minutes -gt 0 ]]; then
      result="${result}${minutes}m$(printf "%02d" ${secs})s"
    else
      result="${result}${secs}s"
    fi
    echo "$result"
  }

  # Function to convert ISO timestamp to epoch (works on both macOS and Linux)
  to_epoch() {
    local ts="$1"
    if [[ "$ts" == "N/A" ]] || [[ -z "$ts" ]]; then
      echo "0"
      return
    fi

    # Try GNU date first (Linux)
    local epoch
    epoch=$(date -u -d "$ts" +%s 2>/dev/null)
    if [[ $? -eq 0 ]]; then
      echo "$epoch"
      return
    fi

    # Try BSD date (macOS) - parse ISO 8601
    # Remove fractional seconds if present
    local clean_ts
    clean_ts=$(echo "$ts" | sed 's/\.[0-9]*Z$/Z/')
    epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$clean_ts" +%s 2>/dev/null)
    if [[ $? -eq 0 ]]; then
      echo "$epoch"
      return
    fi

    echo "0"
  }

  # Convert timestamps to epochs for calculation
  # Use earliest available timestamp as start: ArgoCD App > ClusterInstance > ManagedCluster
  if [[ "${ARGO_APP}" != "N/A" ]]; then
    START_EPOCH=$(to_epoch "${ARGO_APP}")
    START_LABEL="ArgoCD Application Created"
  elif [[ "${CLUSTERINSTANCE}" != "N/A" ]]; then
    START_EPOCH=$(to_epoch "${CLUSTERINSTANCE}")
    START_LABEL="ClusterInstance Created"
  else
    START_EPOCH=$(to_epoch "${GITOPS_SYNC}")
    START_LABEL="GitOps Sync"
  fi

  # Calculate epochs for each milestone
  EPOCH_0=$(to_epoch "${ARGO_APP}")
  EPOCH_0b=$(to_epoch "${CLUSTERINSTANCE}")
  EPOCH_1=$(to_epoch "${GITOPS_SYNC}")
  EPOCH_2=$(to_epoch "${ACI_CREATED}")
  EPOCH_3=$(to_epoch "${ISO_READY}")
  EPOCH_4=$(to_epoch "${AGENT_REG}")
  EPOCH_5=$(to_epoch "${AGENT_BOUND}")
  EPOCH_6=$(to_epoch "${INSTALL_START}")
  EPOCH_7=$(to_epoch "${INSTALL_COMPLETE}")
  EPOCH_8=$(to_epoch "${IMPORT_START}")
  EPOCH_9=$(to_epoch "${CLUSTER_AVAIL}")
  EPOCH_10=$(to_epoch "${POLICIES_DONE}")
  EPOCH_11=$(to_epoch "${TALM_CGU_DONE}")

  # Helper function to calculate total duration
  calc_total() {
    local epoch=$1
    if [[ "$epoch" != "0" ]] && [[ "${START_EPOCH}" != "0" ]]; then
      echo $((epoch - START_EPOCH))
    else
      echo "-1"
    fi
  }

  # Helper function to calculate delta
  calc_delta() {
    local curr=$1
    local prev=$2
    if [[ "$curr" != "0" ]] && [[ "$prev" != "0" ]]; then
      echo $((curr - prev))
    else
      echo "-1"
    fi
  }

  # Create array of milestones with timestamps for sorting
  # Format: "epoch|name|timestamp"
  MILESTONES=(
    "$EPOCH_0|ArgoCD Application Created|${ARGO_APP}"
    "$EPOCH_0b|ClusterInstance Created|${CLUSTERINSTANCE}"
    "$EPOCH_1|GitOps Sync (ManagedCluster Created)|${GITOPS_SYNC}"
    "$EPOCH_2|AgentClusterInstall Created|${ACI_CREATED}"
    "$EPOCH_3|Discovery ISO Ready|${ISO_READY}"
    "$EPOCH_4|Agent Registered|${AGENT_REG}"
    "$EPOCH_5|Agent Bound to Cluster|${AGENT_BOUND}"
    "$EPOCH_6|Installation Started|${INSTALL_START}"
    "$EPOCH_7|Installation Completed|${INSTALL_COMPLETE}"
    "$EPOCH_8|Import to ACM Started|${IMPORT_START}"
    "$EPOCH_10|All Policies Compliant|${POLICIES_DONE}"
    "$EPOCH_11|TALM CGU Completed (Ready for Workloads)|${TALM_CGU_DONE}"
  )

  # Sort milestones by epoch timestamp (field 1)
  IFS=$'\n' SORTED_MILESTONES=($(sort -n -t'|' -k1 <<< "${MILESTONES[*]}"))
  unset IFS

  # Print milestones with durations in chronological order
  printf "%-50s %-26s  %-15s  %s\n" "MILESTONE" "TIMESTAMP" "TOTAL ELAPSED" "DELTA"
  printf "%-50s %-26s  %-15s  %s\n" "---------" "---------" "-------------" "-----"

  PREV_EPOCH=0
  COUNTER=1
  for milestone in "${SORTED_MILESTONES[@]}"; do
    EPOCH=$(echo "$milestone" | cut -d'|' -f1)
    NAME=$(echo "$milestone" | cut -d'|' -f2)
    TIMESTAMP=$(echo "$milestone" | cut -d'|' -f3)

    # Skip N/A milestones (epoch = 0)
    if [[ "$EPOCH" == "0" ]]; then
      continue
    fi

    # Calculate total and delta
    TOTAL=$(calc_total $EPOCH)
    if [[ $PREV_EPOCH -eq 0 ]]; then
      DELTA_STR="START"
    else
      DELTA=$(calc_delta $EPOCH $PREV_EPOCH)
      DELTA_STR="+$(format_duration $DELTA)"
    fi

    printf "%-50s %-26s  %-15s  %s\n" \
      "${COUNTER}. ${NAME}" \
      "${TIMESTAMP}" \
      "$(format_duration $TOTAL)" \
      "${DELTA_STR}"

    PREV_EPOCH=$EPOCH
    COUNTER=$((COUNTER + 1))
  done

  echo ""
  echo "======================================================================"
  echo "WORKLOAD READINESS STATUS"
  echo "======================================================================"

  # Calculate time cluster has been ready for workloads (from ready timestamp to NOW)
  NOW_EPOCH=$(date -u +%s)

  if [[ "${TALM_CGU_DONE}" != "N/A" ]]; then
    TIME_READY_AGO=$((NOW_EPOCH - EPOCH_11))
    echo "✅ Cluster ready for workloads since: ${TALM_CGU_DONE} (since $(format_duration ${TIME_READY_AGO}))"
  elif [[ "${POLICIES_DONE}" != "N/A" ]]; then
    TIME_READY_AGO=$((NOW_EPOCH - EPOCH_10))
    echo "✅ All policies compliant since: ${POLICIES_DONE} (since $(format_duration ${TIME_READY_AGO}))"
  else
    echo "⚠️  Workload readiness not yet achieved"
  fi

  echo ""
  echo "======================================================================"
  echo "MILESTONE BREAKDOWN"
  echo "======================================================================"

  echo "${TIMELINE_DATA}" | jq -r 'group_by(.milestone) | .[] |
  "\n" + .[0].milestone + " (" + (. | length | tostring) + " events)" +
  "\n" + "  First: " + .[0].timestamp + " - " + .[0].event +
  "\n" + "  Last:  " + .[-1].timestamp + " - " + .[-1].event'

  echo ""
  echo "======================================================================"
  echo "FEATURE STATUS"
  echo "======================================================================"
  echo "1. ArgoCD Application Starting Point: ${ARGO_APP_STATUS}"
  if [[ "${ARGO_APP_STATUS}" == "Present" ]]; then
    echo "   ✅ Captured GitOps deployment trigger (earliest possible start)"
    echo "   ✅ Using ArgoCD Application creation as deployment start"
  else
    echo "   ℹ️  ArgoCD Application not found (checked openshift-gitops and argocd namespaces)"
    echo "   ℹ️  Using ClusterInstance or ManagedCluster creation as starting point instead"
  fi
  echo ""
  echo "2. ClusterInstance Tracking: ${CLUSTERINSTANCE_STATUS}"
  if [[ "${CLUSTERINSTANCE_STATUS}" == "Present" ]]; then
    echo "   ✅ Captured SiteConfig v2 operator reconciliation events"
    echo "   ℹ️  Available for SiteConfig v2 deployments"
  else
    echo "   ℹ️  ClusterInstance resource not found (requires SiteConfig v2 operator)"
    echo "   ℹ️  Not critical - SiteConfig v1 deployments don't have ClusterInstance"
  fi
  echo ""
  echo "3. TALM CGU Completion: ${TALM_CGU_STATUS}"
  if [[ "${TALM_CGU_STATUS}" == "Present" ]]; then
    echo "   ✅ Captured accurate policy completion timestamp (ready for workloads)"
    echo "   ✅ Using TALM CGU completedAt as deployment success milestone"
  else
    echo "   ℹ️  TALM ClusterGroupUpgrade not found in ztp-install namespace"
    echo "   ℹ️  Using individual policy compliance events as fallback"
  fi
  echo ""
  echo "======================================================================"
  echo "DEPLOYMENT SUMMARY"
  echo "======================================================================"

  # Calculate deployment time from Agent Bound to Ready for Workloads
  if [[ "${AGENT_BOUND}" != "N/A" ]] && [[ "${TALM_CGU_DONE}" != "N/A" ]]; then
    DEPLOYMENT_DURATION=$(calc_delta ${EPOCH_11} ${EPOCH_5})
    echo "🚀 The deployment took $(format_duration ${DEPLOYMENT_DURATION}) from Agent Bound to Cluster to Ready for Workloads"
  elif [[ "${AGENT_BOUND}" != "N/A" ]] && [[ "${POLICIES_DONE}" != "N/A" ]]; then
    DEPLOYMENT_DURATION=$(calc_delta ${EPOCH_10} ${EPOCH_5})
    echo "🚀 The deployment took $(format_duration ${DEPLOYMENT_DURATION}) from Agent Bound to Cluster to All Policies Compliant"
  elif [[ "${GITOPS_SYNC}" != "N/A" ]] && [[ "${TALM_CGU_DONE}" != "N/A" ]]; then
    DEPLOYMENT_DURATION=$(calc_delta ${EPOCH_11} ${EPOCH_1})
    echo "🚀 The deployment took $(format_duration ${DEPLOYMENT_DURATION}) from GitOps Sync to Ready for Workloads"
  else
    echo "⚠️  Unable to calculate deployment duration (missing key milestones)"
  fi
  echo ""
  echo "======================================================================"
fi

