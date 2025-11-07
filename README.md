# ZTP Deployment Timeline Tracker

Complete toolset for tracking OpenShift Zero Touch Provisioning (ZTP) deployment timelines using Advanced Cluster Management (ACM). These scripts provide detailed insights into every phase of the deployment process, from GitOps sync to policy compliance.

---

## ⚠️ IMPORTANT DISCLAIMERS

### Not an Official Red Hat Tool

**This project is NOT an official Red Hat product, tool, or service.** It is an independent community project and is not supported, endorsed, or maintained by Red Hat, Inc.

### No Red Hat Responsibility

Red Hat, Inc. bears **NO RESPONSIBILITY** for the use, functionality, reliability, or any consequences arising from the use of these scripts. Red Hat provides no warranty, support, or guarantees of any kind for this project.

### No Repository Owner Responsibility

The owner(s) and contributor(s) of this repository provide these scripts **"AS IS" WITHOUT WARRANTY OF ANY KIND**, either express or implied. Users assume **ALL RISKS** associated with the use of these scripts. The repository owner(s) and contributor(s) shall not be held liable for any damages, data loss, system failures, or other issues arising from the use of these tools.

### AI-Generated Content

**These scripts and documentation were generated with the assistance of an AI system** (Claude by Anthropic). While efforts have been made to ensure accuracy and functionality, users should:
- Thoroughly review and test all scripts before use in production environments
- Understand the code and its implications
- Validate outputs against known-good deployments
- Use at their own discretion and risk

### Use At Your Own Risk

By using these scripts, you acknowledge and agree that:
- You have read and understood all disclaimers
- You accept full responsibility for any consequences
- You will test thoroughly in non-production environments first
- You understand this is not supported software
- No warranty or support is provided

---

## 🎯 Overview

Track your ZTP deployment from start to finish with accurate timestamps and phase-by-phase breakdowns:

- **GitOps Sync** → ManagedCluster creation
- **Installation** → OpenShift cluster deployment
- **Discovery & Provisioning** → ISO creation, agent registration, hardware provisioning
- **Import** → ACM integration
- **Policy Application** → Configuration management
- **Completion** → All policies compliant

## ✨ Features

- ✅ **Complete Timeline**: Captures 100+ events across all deployment phases
- ✅ **Accurate Timestamps**: Uses Assisted Service API for precise installation events
- ✅ **Human-Readable Summary**: Clean output with KPI-ready metrics
- ✅ **Cross-Platform**: Works on both macOS and Linux
- ✅ **Remote Execution**: SSH into bastion hosts to query hub clusters
- ✅ **JSON Output**: Machine-readable format for automation

## 📁 Files

### Scripts

- **`get-ztp-deployment-timeline.sh`** - Retrieves complete timeline with all events (JSON output)
- **`summarize-ztp-deployment.sh`** - Human-readable summary with key milestones and KPIs

### Documentation

This README provides:
- Quick start examples
- Sample outputs
- Integration instructions
- Troubleshooting tips

## 🚀 Quick Start

### Prerequisites

- Access to OpenShift cluster via SSH
- `oc` (OpenShift CLI) installed on remote host
- `jq` installed locally and on remote host
- SSH key-based authentication configured

### Example: Basic Timeline Retrieval

```bash
cd scripts

# Get complete timeline (JSON output)
./get-ztp-deployment-timeline.sh \
  --host el-torito.cxm \
  --cluster bull-spoke \
  --kubeconfig /home/carde/clusterconfigs/auth/kubeconfig \
  > bull-spoke-timeline.json

# Get human-readable summary
./summarize-ztp-deployment.sh \
  --host el-torito.cxm \
  --cluster bull-spoke \
  --kubeconfig /home/carde/clusterconfigs/auth/kubeconfig
```

### Example: With Custom SSH Options

```bash
# Using custom SSH key and user
./summarize-ztp-deployment.sh \
  --host el-torito.cxm \
  --ssh-opts "-i ~/.ssh/bull_id_rsa -l carde" \
  --cluster bull-spoke \
  --kubeconfig /home/carde/clusterconfigs/auth/kubeconfig
```

### Example: Local Execution (Already on Hub)

```bash
# If you're already on the hub cluster
./summarize-ztp-deployment.sh \
  --local \
  --cluster bull-spoke \
  --kubeconfig /etc/kubernetes/admin.conf
```

## 📊 Sample Output

### Human-Readable Summary

```
======================================================================
ZTP Deployment Timeline Summary
======================================================================
Hub Cluster: bull-hub
Bastion Host: el-torito.cxm
Spoke Cluster: bull-spoke
ztp-done Label: Present
Total Events Captured: 101

======================================================================
KEY MILESTONES
======================================================================
MILESTONE                                  TIMESTAMP                   TOTAL ELAPSED    DELTA
---------                                  ---------                   -------------    -----
1. AgentClusterInstall Created             2025-11-07T15:38:19Z        0s               START
2. GitOps Sync (ManagedCluster Created)    2025-11-07T15:38:19Z        0s               +0s
3. Import to ACM Started                   2025-11-07T15:38:20Z        1s               +1s
4. Discovery ISO Ready                     2025-11-07T15:38:48Z        29s              +28s
5. Agent Bound to Cluster                  2025-11-07T15:55:26Z        17m7s            +16m38s
6. Agent Registered                        2025-11-07T15:55:26Z        17m7s            +0s
7. Installation Started                    2025-11-07T15:58:13.987Z    19m54s           +2m47s
8. Installation Completed                  2025-11-07T16:15:51Z        37m32s           +17m38s
9. Cluster Available                       2025-11-07T16:43:51Z        1h5m32s          +28m
10. All Policies Compliant                 2025-11-07T17:00:45Z        1h22m26s         +16m54s

======================================================================
MILESTONE BREAKDOWN
======================================================================
1-GITOPS_SYNC (1 events)
  First: 2025-11-07T15:38:19Z
  Last:  2025-11-07T15:38:19Z

2-CLUSTER_INSTALL (33 events)
  First: 2025-11-07T15:38:19Z - AgentClusterInstall.Created
  Last:  2025-11-07T16:15:51Z - AssistedService.ClusterStatus.Installed

3-DISCOVERY (9 events)
  First: 2025-11-07T15:38:19Z - InfraEnv.Created
  Last:  2025-11-07T15:58:13Z - Agent.Bound

4-PROVISIONING (7 events)
  First: 2025-11-07T15:38:48Z - BareMetalHost.Provisioned
  Last:  2025-11-07T15:55:26Z - BareMetalHost.ProvisioningComplete

5-IMPORT (3 events)
  First: 2025-11-07T15:38:19Z - ManagedCluster.Condition.ManagedClusterImportSucceeded
  Last:  2025-11-07T15:38:20Z - ManifestWork.klusterlet-crds

6-MANIFESTWORK (15 events)
  First: 2025-11-07T15:38:20Z - ManifestWork.klusterlet-crds
  Last:  2025-11-07T16:43:51Z - ManifestWork.addon-work-manager-deploy-0

7-POLICY (32 events)
  First: 2025-11-07T15:38:20Z - Policy.common-config-policy
  Last:  2025-11-07T17:00:45Z - Policy.group-du-sno-validator-du-policy

8-CLUSTER_AVAILABLE (1 events)
  First: 2025-11-07T16:43:51Z
  Last:  2025-11-07T16:43:51Z
```

### JSON Output Sample

```json
[
  {
    "timestamp": "2025-11-07T15:38:19Z",
    "event": "ZTP.ManagedClusterCreated",
    "event_description": "ManagedCluster created by GitOps - Start of deployment for bull-spoke",
    "milestone": "1-GITOPS_SYNC"
  },
  {
    "timestamp": "2025-11-07T15:38:19Z",
    "event": "AgentClusterInstall.Created",
    "event_description": "AgentClusterInstall bull-spoke created",
    "milestone": "2-CLUSTER_INSTALL"
  },
  {
    "timestamp": "2025-11-07T15:38:48Z",
    "event": "InfraEnv.ImageCreated",
    "event_description": "Image created and available for download",
    "milestone": "3-DISCOVERY"
  },
  {
    "timestamp": "2025-11-07T15:55:26Z",
    "event": "Agent.Registered",
    "event_description": "Host successfully registered",
    "milestone": "3-DISCOVERY"
  },
  {
    "timestamp": "2025-11-07T15:58:13.987Z",
    "event": "AssistedService.ClusterStatus.Installing",
    "event_description": "Cluster installation is in progress",
    "milestone": "2-CLUSTER_INSTALL"
  },
  {
    "timestamp": "2025-11-07T16:15:51Z",
    "event": "AssistedService.ClusterStatus.Installed",
    "event_description": "Cluster is installed",
    "milestone": "2-CLUSTER_INSTALL"
  },
  {
    "timestamp": "2025-11-07T16:43:51Z",
    "event": "ManagedCluster.Condition.ManagedClusterConditionAvailable",
    "event_description": "ManagedClusterAvailable: Managed cluster is available",
    "milestone": "8-CLUSTER_AVAILABLE"
  },
  {
    "timestamp": "2025-11-07T17:00:45Z",
    "event": "Policy.group-du-sno-validator-du-policy",
    "event_description": "Compliant",
    "milestone": "7-POLICY"
  }
]
```

## 🎯 Use Cases

### 1. KPI Tracking

Track deployment performance metrics:

```bash
# Run summary for each deployment
./summarize-ztp-deployment.sh \
  --host el-torito.cxm \
  --cluster bull-spoke \
  --kubeconfig /home/carde/clusterconfigs/auth/kubeconfig \
  | tee bull-spoke-kpis.txt

# Key metrics:
# - Total deployment time: GitOps → All Policies Compliant
# - Installation time: Installation Started → Completed
# - Import time: Import Started → Cluster Available
# - Policy application time: Available → Policies Compliant
```

### 2. Troubleshooting Failed Deployments

Identify where deployments get stuck:

```bash
# Get timeline even for failed deployments
./get-ztp-deployment-timeline.sh \
  --host el-torito.cxm \
  --cluster bull-spoke-failed \
  --kubeconfig /home/carde/clusterconfigs/auth/kubeconfig \
  | jq '.[].event_description' | grep -i "error\|fail"

# Look for last successful event
./summarize-ztp-deployment.sh \
  --host el-torito.cxm \
  --cluster bull-spoke-failed \
  --kubeconfig /home/carde/clusterconfigs/auth/kubeconfig
```

### 3. Comparing Deployments

Compare multiple cluster deployments:

```bash
# Get timelines for multiple clusters
for cluster in bull-spoke-01 bull-spoke-02 bull-spoke-03; do
  ./get-ztp-deployment-timeline.sh \
    --host el-torito.cxm \
    --cluster $cluster \
    --kubeconfig /home/carde/clusterconfigs/auth/kubeconfig \
    > ${cluster}-timeline.json
done

# Compare total deployment times
for cluster in bull-spoke-01 bull-spoke-02 bull-spoke-03; do
  echo -n "$cluster: "
  ./summarize-ztp-deployment.sh \
    --host el-torito.cxm \
    --cluster $cluster \
    --kubeconfig /home/carde/clusterconfigs/auth/kubeconfig \
    | grep "All Policies Compliant" | awk '{print $4}'
done
```

### 4. CI/CD Integration

Integrate into CI/CD pipelines:

```bash
#!/bin/bash
# Example: Post-deployment validation

CLUSTER_NAME="bull-spoke"
HOST="el-torito.cxm"
KUBECONFIG="/home/carde/clusterconfigs/auth/kubeconfig"

# Get deployment timeline
./summarize-ztp-deployment.sh \
  --host $HOST \
  --cluster $CLUSTER_NAME \
  --kubeconfig $KUBECONFIG \
  > ${CLUSTER_NAME}-deployment-summary.txt

# Check if ztp-done label is present
ZTP_DONE=$(grep "ztp-done Label:" ${CLUSTER_NAME}-deployment-summary.txt | awk '{print $3}')

if [[ "$ZTP_DONE" == "Present" ]]; then
  echo "✅ Deployment complete: ztp-done label present"
  exit 0
else
  echo "❌ Deployment incomplete: ztp-done label not present"
  exit 1
fi
```

## 📖 Script Parameters

### get-ztp-deployment-timeline.sh

| Parameter | Required | Description | Example |
|-----------|----------|-------------|---------|
| `--host` | Yes (unless --local) | SSH host to connect to | `el-torito.cxm` |
| `--ssh-opts` | No | Additional SSH options | `"-i ~/.ssh/bull_id_rsa -l carde"` |
| `--cluster` | Yes | Spoke cluster name | `bull-spoke` |
| `--kubeconfig` | Yes | Path to kubeconfig on remote host | `/home/carde/clusterconfigs/auth/kubeconfig` |
| `--local` | No | Run locally (skip SSH) | `--local` |

### summarize-ztp-deployment.sh

Same parameters as above, plus:

| Parameter | Required | Description | Example |
|-----------|----------|-------------|---------|
| `--json` | No | Output summary as JSON | `--json` |

## 🔍 What Gets Tracked

### Phase 1: GitOps Sync (T+0s)
- ManagedCluster resource creation
- Initial import conditions

### Phase 2: Cluster Installation (T+0s to T+37m)
- AgentClusterInstall creation and conditions
- ClusterDeployment events
- **Assisted Service API events** (precise timestamps):
  - Preparing for installation
  - Installing
  - Finalizing
  - Installed

### Phase 3: Discovery (T+0s to T+17m)
- InfraEnv creation
- Discovery ISO generation
- Agent registration
- Agent bound to cluster

### Phase 4: Provisioning (T+29s to T+17m)
- BareMetalHost provisioning
- Hardware registration
- Power on/off events

### Phase 5: Import (T+0s to T+1s)
- ManifestWork creation (klusterlet)
- ACM agent deployment

### Phase 6: ManifestWork (T+1s to T+1h5m)
- ACM addon deployments
- klusterlet-crds, application-manager, cert-policy-controller, etc.

### Phase 7: Policy Application (T+1s to T+1h22m)
- Policy status changes (empty → NonCompliant → Compliant)
- Common policies, DU policies, site-specific policies

### Phase 8: Cluster Available (T+1h5m)
- ManagedCluster condition: Available

### Final: All Policies Compliant (T+1h22m) ✅
- **This is the deployment completion milestone**
- All configuration applied
- Cluster ready for workloads

### ztp-done Label
- Shown as **boolean status** in header (Present/Not Present)
- **Not a timed milestone** (no accurate timestamp available)
- Use for verification, not KPI calculations

## 🎨 Milestone Breakdown

The summary shows events grouped by milestone category:

```
1-GITOPS_SYNC       Initial ManagedCluster creation
2-CLUSTER_INSTALL   OpenShift installation process
3-DISCOVERY         ISO creation, agent registration
4-PROVISIONING      BareMetalHost hardware provisioning
5-IMPORT            Initial ACM import
6-MANIFESTWORK      ACM addon deployments
7-POLICY            Policy application and compliance
8-CLUSTER_AVAILABLE Cluster joins ACM and is available
```

## ⚙️ Configuration

### SSH Configuration

For easier use, configure SSH in `~/.ssh/config`:

```
Host el-torito
    HostName el-torito.cxm
    User carde
    IdentityFile ~/.ssh/bull_id_rsa
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
```

Then use simplified commands:

```bash
./summarize-ztp-deployment.sh \
  --host el-torito \
  --cluster bull-spoke \
  --kubeconfig /home/carde/clusterconfigs/auth/kubeconfig
```

### Environment Variables

Set defaults to simplify repeated commands:

```bash
export ZTP_HOST="el-torito.cxm"
export ZTP_SSH_OPTS="-i ~/.ssh/bull_id_rsa -l carde"
export ZTP_KUBECONFIG="/home/carde/clusterconfigs/auth/kubeconfig"

# Then use:
./summarize-ztp-deployment.sh \
  --host $ZTP_HOST \
  --ssh-opts "$ZTP_SSH_OPTS" \
  --cluster bull-spoke \
  --kubeconfig $ZTP_KUBECONFIG
```

## 🐛 Troubleshooting

### Error: "command not found: oc"

**Problem**: OpenShift CLI not in PATH on remote host

**Solution**: Ensure `oc` is installed and accessible:
```bash
ssh carde@el-torito.cxm "which oc"
# If not found, install oc or add to PATH
```

### Error: "command not found: jq"

**Problem**: jq not installed locally or on remote host

**Solution**: Install jq:
```bash
# On macOS
brew install jq

# On RHEL/CentOS
sudo yum install jq

# On Ubuntu/Debian
sudo apt install jq
```

### Error: "ssh_cmd: unbound variable"

**Problem**: Script variable issue (should be fixed in latest version)

**Solution**: Ensure you're using the latest version of the scripts

### Error: "The server doesn't have a resource type 'managedcluster'"

**Problem**: Not connected to hub cluster or ACM not installed

**Solution**: Verify kubeconfig points to hub cluster:
```bash
ssh carde@el-torito.cxm "oc --kubeconfig /home/carde/clusterconfigs/auth/kubeconfig get managedclusters"
```

### No Events Found

**Problem**: Cluster name might be incorrect or cluster doesn't exist

**Solution**: List available clusters:
```bash
ssh carde@el-torito.cxm "oc --kubeconfig /home/carde/clusterconfigs/auth/kubeconfig get managedclusters"
```

### "Installation Started: N/A"

**Problem**: Assisted Service API events not available (older ACM versions or API not accessible)

**Solution**: This is a known limitation. The script will still show other milestones. Consider:
- Checking ACM version (requires ACM 2.6+)
- Verifying Assisted Service pods are running
- Using "Agent.Bound" as proxy for installation start

## 📈 Performance Benchmarks

Typical timeline for successful ZTP deployment:

| Phase | Duration | Description |
|-------|----------|-------------|
| GitOps → ISO Ready | ~30s | Initial resources creation |
| ISO Ready → Agent Registered | ~16m | Host boot and discovery |
| Agent Registered → Installation Started | ~3m | Pre-installation validation |
| Installation Started → Completed | ~17m | OpenShift installation |
| Installation Complete → Available | ~28m | Cluster join and handshake |
| Available → Policies Compliant | ~17m | Configuration application |
| **Total Deployment** | **~1h22m** | **Complete ZTP workflow** |

**Variance**: ±15 minutes depending on:
- Hardware specifications
- Network speed
- Policy complexity
- Operator installation times

## 🔐 Security Considerations

- Scripts execute remote commands via SSH (read-only `oc get` and API queries)
- No modifications are made to any cluster
- Ensure SSH keys are properly secured (chmod 600)
- Consider using SSH key passphrases
- Audit remote command execution if required by security policies

## 🤝 Contributing

To improve these scripts:

1. Test with different ACM versions
2. Add support for additional event types
3. Improve error handling
4. Add more output formats (CSV, HTML)

## 📝 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

### Apache License 2.0 Summary

- ✅ Commercial use allowed
- ✅ Modification allowed
- ✅ Distribution allowed
- ✅ Patent use allowed
- ✅ Private use allowed
- ⚠️ Liability and warranty disclaimers apply
- ⚠️ Must include license and copyright notice
- ⚠️ Must state changes made to the code

For the complete license text, see the [LICENSE](LICENSE) file in this repository.

## 🆘 Support

**IMPORTANT**: This is a community project with **NO OFFICIAL SUPPORT**.

For issues or questions:
1. Check the troubleshooting section
2. Review script output for error messages
3. Verify SSH connectivity and credentials
4. Confirm `oc` and `jq` are installed and accessible
5. Open an issue in the GitHub repository (community support only)

**Remember**: No warranty or guarantee of support is provided.

## 🎓 Additional Resources

- [OpenShift Documentation](https://docs.openshift.com/)
- [ACM Documentation](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/)
- [ZTP GitOps Pattern](https://docs.openshift.com/container-platform/latest/scalability_and_performance/ztp_far_edge/ztp-deploying-far-edge-sites.html)
- [Assisted Installer](https://github.com/openshift/assisted-service)

---

**Version**: 2.0  
**Last Updated**: November 2025  
**Compatibility**: ACM 2.6+, OpenShift 4.12+  
**License**: Apache License 2.0  
**AI-Generated**: Scripts and documentation created with AI assistance

