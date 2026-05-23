# Ansible Provisioning

## Purpose
This directory contains the automation used to configure the full local platform.

## Execution Model
The playbook is organized into ordered plays:
1. `common`, `nfs_client`, `containerd`, `kubernetes` on all Kubernetes nodes.
2. `master` and `cni` on control-plane nodes.
3. `workers` on worker nodes.
4. Validation from the master.
5. `common` and `nfs_server` on the services VM.

## Role Map
- `common`: OS and kernel prerequisites.
- `containerd`: container runtime.
- `kubernetes`: kubeadm/kubelet/kubectl installation.
- `master`: control-plane bootstrap.
- `workers`: worker joins.
- `cni`: Flannel networking.
- `nfs_client`: NFS client packages on cluster nodes.
- `nfs_server`: NFS exports on the services VM.
- `docker`: Docker runtime and registry access.
- `gitea`: source control service.
- `nexus`: Docker registry.
- `mysql`: database stack.
- `backend`: API deployment.
- `frontend`: UI deployment.
- `jenkins`: CI/CD controller deployment.

## How To Run
- Full cluster: `vagrant up`
- Re-run configuration only: `vagrant provision`
- Targeted roles: `ansible-playbook -i inventory.ini playbook.yml --tags <tag>`

## What To Read Next
- [Architecture](../docs/ARCHITECTURE.md)
- [Root README](../README.md)
