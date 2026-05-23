# Master Role

## Purpose
This role initializes the Kubernetes control plane on `k8s-master`.

## What It Does
- Runs `kubeadm init`.
- Configures the admin kubeconfig for the `vagrant` user.
- Captures the worker join command.
- Makes the cluster ready for CNI installation.

## Data Flow
1. Base Kubernetes packages are already installed.
2. The master initializes the control plane.
3. The API server starts on the master IP.
4. A join command is produced for the worker nodes.
5. The CNI role deploys networking after the control plane is healthy.

## Key File
- `tasks/main.yml`
