# CNI Role

## Purpose
This role deploys Flannel, the cluster network overlay.

## What It Does
- Downloads the Flannel manifest.
- Applies it to the cluster.
- Waits for the Flannel DaemonSet to become ready.

## Data Flow
1. Kubernetes nodes come up without pod networking.
2. The CNI role applies the Flannel manifest.
3. Flannel pod networking becomes available across master and workers.
4. Pods can resolve and reach services across nodes.

## Why It Matters
Without CNI, the cluster may show nodes as present but pods will not communicate correctly.

## Key File
- `tasks/main.yml`
