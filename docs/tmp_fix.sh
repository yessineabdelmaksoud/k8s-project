#!/bin/bash
mkdir -p /tmp
cat ~/.kube/config | sed 's/127.0.0.1/192.168.56.10/g' | sed 's/localhost/192.168.56.10/g' > /tmp/cfg
JENKINS_POD=$(kubectl get pods -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n jenkins ${JENKINS_POD} -- mkdir -p /var/jenkins_home/.kube
kubectl cp /tmp/cfg jenkins/${JENKINS_POD}:/var/jenkins_home/.kube/config
kubectl exec -n jenkins ${JENKINS_POD} -- chmod 600 /var/jenkins_home/.kube/config
echo "Success!"
