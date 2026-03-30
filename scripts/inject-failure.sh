#!/bin/bash
# Chaos Injection Script for Self-Healing AKS Demo
# Usage: ./inject-failure.sh [crash|oom|scale]

set -e

NAMESPACE="demo-app"
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_NC='\033[0m'

log_info() {
    echo -e "${COLOR_GREEN}[INFO]${COLOR_NC} $1"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_NC} $1"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_NC} $1"
}

# Inject crash loop failure
inject_crash() {
    log_info "Deploying crash loop pod..."
    kubectl apply -f ../k8s/demo-app/chaos-pod.yaml
    
    log_warn "Pod 'crash-loop-demo' will crash every 30 seconds"
    log_info "Watch the self-healing with: kubectl get pods -n $NAMESPACE -w"
    log_info "View alerts: kubectl port-forward svc/monitoring-alertmanager 9093:9093 -n monitoring"
}

# Inject memory pressure
inject_oom() {
    log_info "Deploying memory hog pod..."
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: memory-hog-$(date +%s)
  namespace: $NAMESPACE
  labels:
    chaos: "true"
spec:
  containers:
    - name: memory-hog
      image: python:3.11-alpine
      command: ["python", "-c", "data=[]; [data.append('x'*(10*1024*1024)) or __import__('time').sleep(0.5) for _ in range(100)]"]
      resources:
        limits:
          memory: "128Mi"
EOF
    
    log_warn "Memory hog pod deployed - will OOM soon"
    log_info "Watch with: kubectl get pods -n $NAMESPACE -w"
}

# Scale deployment to zero (simulate outage)
inject_scale() {
    log_info "Scaling demo-api to 0 replicas..."
    kubectl scale deployment demo-api -n $NAMESPACE --replicas=0
    
    log_warn "demo-api scaled to 0 - simulating outage"
    log_info "The HPA or alerting should detect this and scale back up"
    log_info "Or manually restore with: kubectl scale deployment demo-api -n $NAMESPACE --replicas=2"
}

# Cleanup chaos resources
cleanup() {
    log_info "Cleaning up chaos resources..."
    kubectl delete pods -n $NAMESPACE -l chaos=true --ignore-not-found
    kubectl scale deployment demo-api -n $NAMESPACE --replicas=2 --ignore-not-found || true
    log_info "Cleanup complete"
}

# Show usage
usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  crash   - Deploy a crash-looping pod"
    echo "  oom     - Deploy a memory hog pod"
    echo "  scale   - Scale deployment to zero"
    echo "  cleanup - Remove all chaos resources"
    echo ""
}

# Main
case "${1:-}" in
    crash)
        inject_crash
        ;;
    oom)
        inject_oom
        ;;
    scale)
        inject_scale
        ;;
    cleanup)
        cleanup
        ;;
    *)
        usage
        exit 1
        ;;
esac

