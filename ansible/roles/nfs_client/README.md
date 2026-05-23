# NFS Client Role

## Purpose
This role installs the client-side NFS utilities required by Kubernetes nodes that mount NFS-backed volumes.

## What It Does
- Installs `nfs-common` on Kubernetes nodes.

## Data Flow
1. The NFS server exports shared directories from the `services` VM.
2. Kubernetes creates PersistentVolumes that reference those exports.
3. Worker nodes need NFS client utilities to mount the storage successfully.

## Why It Exists
Without the client package, pods cannot mount NFS-backed volumes even if the server and PV definitions are correct.

## Key File
- `tasks/main.yml`
