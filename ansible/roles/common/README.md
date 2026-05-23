# Common Role

## Purpose
This role prepares every Kubernetes node with the operating-system prerequisites required by kubeadm, kubelet, and the container runtime.

## What It Does
- Disables swap at runtime and removes swap entries from `/etc/fstab`.
- Loads the `overlay` and `br_netfilter` kernel modules.
- Writes persistent module and sysctl configuration.
- Installs shared system packages.
- Adds cluster hostnames to `/etc/hosts`.

## Data Flow
1. The role runs on all Kubernetes nodes and the services VM.
2. The operating system is normalized so Kubernetes can bootstrap reliably.
3. Kernel and networking settings are applied before the control plane starts.
4. Hostname resolution is prepared so nodes can reach each other by name.

## Why It Matters
Kubernetes is sensitive to swap, kernel, and networking configuration. This role removes those risks before any cluster component is installed.

## Key Files
- `tasks/main.yml`
- `handlers/main.yml`
