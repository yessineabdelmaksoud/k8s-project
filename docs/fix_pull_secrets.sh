#!/bin/bash
# Remove existing if they exist
kubectl delete secret nexus-regsecret -n backend --ignore-not-found
kubectl delete secret nexus-regsecret -n frontend --ignore-not-found

# Create new ones
kubectl create secret docker-registry nexus-regsecret \
  --docker-server=192.168.56.20:8082 \
  --docker-username=admin \
  --docker-password=admin123 \
  -n backend

kubectl create secret docker-registry nexus-regsecret \
  --docker-server=192.168.56.20:8082 \
  --docker-username=admin \
  --docker-password=admin123 \
  -n frontend

# Patch deployments
kubectl patch deployment backend -n backend -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"nexus-regsecret"}]}}}}'
kubectl patch deployment frontend -n frontend -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"nexus-regsecret"}]}}}}'

# Restart to force pull
kubectl rollout restart deployment backend -n backend
kubectl rollout restart deployment frontend -n frontend

echo "Success: Secrets created and deployments patched!"
