# NFS Server Role

## Purpose
This role prepares the shared storage exported by the `services` VM for Kubernetes persistent volumes.

## What It Exports
- `/srv/nfs/k8s` for general cluster storage.
- `/srv/nfs/jenkins` for Jenkins home storage.

## Data Flow
1. The NFS server is installed on the `services` VM.
2. Export directories are created and published through `/etc/exports`.
3. Kubernetes PersistentVolumes point to the NFS paths.
4. Pods such as MySQL or Jenkins mount those volumes and keep their data across restarts.

## Implementation Notes
- The exports allow the 192.168.56.0/24 network to read and write the shared storage.
- `no_root_squash` keeps the local lab environment simple, but it is not a production default.

## Key File
- `tasks/main.yml`
