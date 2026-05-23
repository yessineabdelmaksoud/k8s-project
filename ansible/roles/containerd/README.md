# Containerd Role

## Purpose
This role installs and configures the container runtime used by every Kubernetes node.

## What It Does
- Installs containerd.
- Configures it to use the systemd cgroup driver.
- Starts and enables the service.

## Data Flow
1. Kubernetes schedules a pod on a node.
2. Kubelet asks containerd to create and manage the container.
3. containerd pulls the image and starts the container runtime process.

## Why the cgroup setting matters
Kubernetes and containerd must agree on cgroup management. Using `SystemdCgroup` avoids common kubelet/runtime mismatches.

## Key File
- `tasks/main.yml`
- `handlers/main.yml`
