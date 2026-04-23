#!/bin/bash
# =============================================================================
# jenkins-kubectl-setup.sh — Verify Jenkins K8s pod has proper access
# =============================================================================
# Run this script from the services VM or via vagrant ssh.
# Jenkins is now a K8s pod with:
#   - ServiceAccount (cluster-admin) → kubectl works automatically
#   - Docker binary mounted from host → docker build/push works
#   - Docker socket mounted from host → communicates with Docker daemon
# =============================================================================

set -e

echo "=== Verifying Jenkins pod in K8s ==="

# 1. Find Jenkins pod
echo ""
echo "=== Step 1: Find Jenkins pod ==="
JENKINS_POD=$(ssh -o StrictHostKeyChecking=no vagrant@192.168.56.10 \
    "kubectl get pods -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}' 2>/dev/null")

if [ -z "$JENKINS_POD" ]; then
    echo "  ERROR: Jenkins pod not found. Is it running?"
    echo "  Check: vagrant ssh k8s-master -c 'kubectl get pods -n jenkins'"
    exit 1
fi
echo "  Jenkins pod: ${JENKINS_POD}"

# 2. Verify kubectl access
echo ""
echo "=== Step 2: Verify kubectl access (via ServiceAccount) ==="
ssh -o StrictHostKeyChecking=no vagrant@192.168.56.10 \
    "kubectl exec -n jenkins ${JENKINS_POD} -- kubectl get nodes"

# 3. Verify Docker access
echo ""
echo "=== Step 3: Verify Docker access (via docker.sock) ==="
ssh -o StrictHostKeyChecking=no vagrant@192.168.56.10 \
    "kubectl exec -n jenkins ${JENKINS_POD} -- docker info --format '{{.ServerVersion}}'" 2>/dev/null && \
    echo "  Docker access OK" || echo "  WARNING: Docker not accessible in Jenkins pod"

# 4. Verify Docker registry connectivity
echo ""
echo "=== Step 4: Verify Nexus registry access ==="
ssh -o StrictHostKeyChecking=no vagrant@192.168.56.10 \
    "kubectl exec -n jenkins ${JENKINS_POD} -- docker login 192.168.56.20:8082 -u admin -p admin123" 2>/dev/null && \
    echo "  Nexus registry login OK" || echo "  WARNING: Cannot login to Nexus registry"

echo ""
echo "=== Jenkins K8s verification complete! ==="
echo "  Jenkins UI: http://192.168.56.11:32000 (or http://192.168.56.12:32000)"
echo ""
echo "  Get initial admin password:"
echo "  vagrant ssh k8s-master -c \"kubectl exec -n jenkins ${JENKINS_POD} -- cat /var/jenkins_home/secrets/initialAdminPassword\""
