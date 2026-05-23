#!/bin/bash
set -euo pipefail

JENKINS_POD=$(kubectl get pods -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n jenkins ${JENKINS_POD} -- mkdir -p /var/jenkins_home/.kube

cat <<EOF > /tmp/jenkins-kubeconfig
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    server: https://kubernetes.default.svc:443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: jenkins
  name: jenkins
current-context: jenkins
preferences: {}
users:
- name: jenkins
  user:
    tokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
EOF

kubectl cp /tmp/jenkins-kubeconfig jenkins/${JENKINS_POD}:/var/jenkins_home/.kube/config
kubectl exec -n jenkins ${JENKINS_POD} -- chmod 600 /var/jenkins_home/.kube/config
echo "Jenkins KUBECONFIG updated to use in-cluster ServiceAccount tokenFile."
