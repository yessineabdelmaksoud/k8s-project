# Jenkins Role

## Purpose
This role deploys Jenkins as a Kubernetes workload in the `jenkins` namespace and prepares it for CI/CD execution against the cluster.

## What It Installs
- Jenkins deployment and service.
- Persistent storage for `/var/jenkins_home`.
- A ServiceAccount with cluster-admin privileges.
- A kubeconfig inside the Jenkins pod so pipelines can call `kubectl`.

## Data Flow
1. Ansible copies the Jenkins manifests to the master node.
2. Kubernetes creates the namespace, RBAC objects, storage, service, and deployment.
3. Jenkins starts in the cluster and mounts persistent storage.
4. The role writes `/var/jenkins_home/.kube/config` inside the running pod.
5. Jenkins pipelines use that config to deploy backend and frontend updates.

## Why the kubeconfig matters
The kubeconfig is generated to use in-cluster Kubernetes service discovery and the mounted ServiceAccount token file. That avoids brittle configs tied to a static IP or a manually copied token.

## Key Files
- `files/deployment.yaml`
- `files/service.yaml`
- `files/serviceaccount.yaml`
- `files/pv.yaml`
- `files/pvc.yaml`
- `tasks/main.yml`

## Operational Notes
- The Jenkins Service is exposed as `NodePort` on `32000`.
- Pipelines expect the `nexus-credentials` credential to exist in Jenkins.
- The backend and frontend jobs both use the same general deploy pattern: build, push, set image, verify rollout.
