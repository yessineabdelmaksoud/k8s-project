# Kubernetes Cluster — Local Development Environment

## Overview

Fully automated Kubernetes cluster provisioned locally using **Vagrant** and **Ansible**.

| Node | Hostname | IP | CPU | RAM | Role |
|------|----------|----|-----|-----|------|
| Master | k8s-master | 192.168.56.10 | 2 | 4 GB | Control plane |
| Worker 1 | k8s-worker1 | 192.168.56.11 | 2 | 2 GB | Workload node |
| Worker 2 | k8s-worker2 | 192.168.56.12 | 2 | 2 GB | Workload node |
| Services | services | 192.168.56.20 | 2 | 4 GB | CI/CD, monitoring |

**Stack:** Ubuntu 22.04 · Kubernetes 1.29.2 · containerd · Flannel CNI · kubeadm

---

## Prerequisites

Install the following on your host machine:

- [Vagrant](https://www.vagrantup.com/downloads) (>= 2.3)
- [VirtualBox](https://www.virtualbox.org/wiki/Downloads) (>= 7.0)
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) (>= 2.14)

> **Windows users:** Ansible runs on the host via Vagrant's Ansible provisioner.
> Ensure Ansible is accessible from your terminal (WSL or Git Bash recommended).

---

## Project Structure

```
cluster/
├── Vagrantfile                          # VM definitions & Ansible provisioner
├── ansible/
│   ├── inventory.ini                    # Static inventory with groups
│   ├── group_vars/
│   │   └── all.yml                      # Shared variables (versions, IPs, etc.)
│   ├── roles/
│   │   ├── common/                      # Swap, kernel modules, sysctl, packages
│   │   │   ├── tasks/main.yml
│   │   │   └── handlers/main.yml
│   │   ├── containerd/                  # Container runtime
│   │   │   ├── tasks/main.yml
│   │   │   └── handlers/main.yml
│   │   ├── kubernetes/                  # kubeadm, kubelet, kubectl
│   │   │   └── tasks/main.yml
│   │   ├── master/                      # Control plane init + join command
│   │   │   └── tasks/main.yml
│   │   ├── workers/                     # Worker join
│   │   │   └── tasks/main.yml
│   │   └── cni/                         # Flannel deployment
│   │       └── tasks/main.yml
│   └── playbook.yml                     # Main playbook (execution order)
└── README.md                            # This file
```

---

## Quick Start

### 1. Provision the entire cluster

```bash
vagrant up
```

This single command will:
1. Create 4 Ubuntu 22.04 VMs in VirtualBox
2. Run the Ansible playbook automatically after all VMs are ready
3. Initialize the Kubernetes control plane on `k8s-master`
4. Join `k8s-worker1` and `k8s-worker2` to the cluster
5. Deploy the Flannel CNI plugin
6. Validate the cluster and display node/pod status

### 2. Access the cluster

```bash
# SSH into any node
vagrant ssh k8s-master
vagrant ssh k8s-worker1
vagrant ssh k8s-worker2
vagrant ssh services
```

### 3. Verify the cluster

```bash
vagrant ssh k8s-master -c "kubectl get nodes"
```

Expected output:
```
NAME          STATUS   ROLES           AGE   VERSION
k8s-master    Ready    control-plane   5m    v1.29.2
k8s-worker1   Ready    <none>          3m    v1.29.2
k8s-worker2   Ready    <none>          3m    v1.29.2
```

```bash
vagrant ssh k8s-master -c "kubectl get pods -A"
```

Expected pods — all `Running`:
- `coredns-*` (2 pods)
- `etcd-k8s-master`
- `kube-apiserver-k8s-master`
- `kube-controller-manager-k8s-master`
- `kube-proxy-*` (3 pods)
- `kube-scheduler-k8s-master`
- `kube-flannel-ds-*` (3 pods)

---

## Ansible Execution Flow

```
Play 1 — k8s_cluster (master + workers)
  └── common       → swap, modules, sysctl, packages, /etc/hosts
  └── containerd   → install, config, SystemdCgroup, start
  └── kubernetes   → apt repo, kubelet/kubeadm/kubectl, hold, enable

Play 2 — masters
  └── master       → kubeadm init, kubectl config, join command
  └── cni          → Flannel deployment

Play 3 — workers
  └── workers      → kubeadm join (dynamic token from master)

Play 4 — masters
  └── validation   → kubectl get nodes, kubectl get pods -A

Play 5 — services
  └── common       → base packages (ready for future services)
```

---

## Management Commands

```bash
# Stop all VMs (preserving state)
vagrant halt

# Restart all VMs
vagrant up

# Re-run Ansible provisioning only
vagrant provision

# Destroy all VMs completely
vagrant destroy -f

# Check VM status
vagrant status
```

---

## Configuration

All configurable values are in [`ansible/group_vars/all.yml`](ansible/group_vars/all.yml):

| Variable | Default | Description |
|----------|---------|-------------|
| `kube_version` | `1.29.2-1.1` | Pinned Kubernetes APT package version |
| `kube_major_version` | `1.29` | Used for APT repository URL |
| `pod_network_cidr` | `10.244.0.0/16` | Pod network CIDR (Flannel default) |
| `master_ip` | `192.168.56.10` | API server advertise address |
| `flannel_manifest_url` | `...kube-flannel.yml` | Flannel deployment manifest |

---

## Design Decisions

- **Idempotent tasks only** — Every role can be re-run safely without side effects
- **No manual steps** — `vagrant up` handles everything end-to-end
- **Explicit versioning** — Kubernetes packages are pinned and held
- **Dynamic join token** — Worker join command is extracted from the master at runtime
- **Ansible provisioner on last VM** — Ensures all VMs exist before any configuration begins
- **Services node separated** — Not part of the K8s cluster; reserved for CI/CD, monitoring, etc.

---

## Troubleshooting

```bash
# Re-provision with verbose output
ANSIBLE_VERBOSITY=3 vagrant provision

# Check kubelet logs on a node
vagrant ssh k8s-master -c "sudo journalctl -u kubelet -f"

# Reset a node's Kubernetes state (use with caution)
vagrant ssh k8s-worker1 -c "sudo kubeadm reset -f"
```
