# Self-Healing AKS Cluster

[![Azure Kubernetes](https://img.shields.io/badge/AKS-Enabled-blue?logo=kubernetes)](.)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Prometheus](https://img.shields.io/badge/Prometheus-Monitoring-orange?logo=prometheus)](https://prometheus.io/)

A **self-healing Kubernetes cluster** on Azure that automatically detects failures and remediates them without human intervention. Classic SRE automation - "I don't just monitor, I fix it automatically."

## What This Project Demonstrates

- **Auto-remediation**: Automatic recovery from common failure scenarios
- **Observability**: Full monitoring stack with Prometheus & Grafana
- **Chaos Engineering**: Built-in failure injection for testing
- **GitOps Ready**: Infrastructure as Code with Bicep

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Self-Healing AKS Cluster                        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        ▼                           ▼                           ▼
┌──────────────┐           ┌──────────────┐           ┌──────────────┐
│     AKS      │           │  Prometheus  │           │   Grafana    │
│   Cluster    │◀─────────▶│  Monitoring  │──────────▶│  Dashboard   │
└──────────────┘           └──────────────┘           └──────────────┘
        │                           │
        │                           ▼
        │                  ┌──────────────┐
        │                  │ Alert Manager│
        │                  └──────────────┘
        │                           │
        ▼                           ▼
┌──────────────┐           ┌──────────────┐
│   Workload   │           │  Azure Logic │
│    Pods      │◀──────────│     App      │
└──────────────┘  Restart  │ (Remediation)│
                           └──────────────┘

Self-Healing Flow:
1. Pod fails / becomes unhealthy
2. Prometheus detects via metrics
3. AlertManager fires alert
4. Logic App receives webhook
5. Logic App triggers remediation (restart/scale)
6. Notification sent to Teams/Slack
```

## Self-Healing Capabilities

| Failure Type | Detection | Remediation |
|-------------|-----------|-------------|
| Pod CrashLoop | Restart count > 5 | Delete pod (reschedule) |
| High Memory | Memory > 90% | Scale out deployment |
| Node Not Ready | Node status | Cordon + drain + restart |
| Pending Pods | Pod phase = Pending > 5min | Scale node pool |
| Certificate Expiry | Cert-manager metrics | Trigger renewal |

## Quick Start

### Prerequisites
- Azure subscription
- Azure CLI installed
- kubectl configured
- Helm 3.x

### Deploy Infrastructure
```bash
# Login to Azure
az login

# Create resource group
az group create -n rg-self-healing-aks -l eastus

# Deploy AKS cluster with Bicep
az deployment group create \
  -g rg-self-healing-aks \
  -f infra/main.bicep \
  -p environment=dev

# Get AKS credentials
az aks get-credentials -g rg-self-healing-aks -n aks-selfheal-dev
```

### Install Monitoring Stack
```bash
# Add Helm repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus + Grafana
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f k8s/monitoring/values.yaml
```

### Deploy Demo Application
```bash
# Deploy sample app with chaos capabilities
kubectl apply -f k8s/demo-app/

# Deploy remediation Logic App
az deployment group create \
  -g rg-self-healing-aks \
  -f infra/logic-app.bicep
```

## Project Structure

```
├── infra/
│   ├── main.bicep              # AKS cluster infrastructure
│   ├── logic-app.bicep         # Remediation Logic App
│   └── modules/
│       └── aks.bicep           # AKS module
├── k8s/
│   ├── monitoring/
│   │   ├── values.yaml         # Prometheus/Grafana config
│   │   └── alerting-rules.yaml # Custom alerting rules
│   ├── demo-app/
│   │   ├── deployment.yaml     # Sample application
│   │   └── chaos-pod.yaml      # Chaos engineering pod
│   └── remediation/
│       └── rbac.yaml           # Service account for remediation
├── scripts/
│   ├── inject-failure.sh       # Chaos testing script
│   └── demo.sh                 # Full demo script
└── README.md
```

## Demo: Trigger Self-Healing

```bash
# Inject a failure (pod crash)
./scripts/inject-failure.sh crash

# Watch the self-healing in action
kubectl get pods -w

# View in Grafana
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
# Open http://localhost:3000 (admin/prom-operator)
```

## Grafana Dashboards

- **Cluster Overview**: Node health, resource usage
- **Pod Health**: Restart counts, ready status
- **Self-Healing Metrics**: Remediation events, MTTR

## License

MIT License - see [LICENSE](LICENSE) for details.

---

**Built for resilient infrastructure**

