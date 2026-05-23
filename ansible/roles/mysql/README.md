# MySQL Role

## Purpose
This role deploys the database layer of the application as a Kubernetes StatefulSet in the `database` namespace.

## What It Deploys
- Namespace `database`.
- PersistentVolume and PersistentVolumeClaim.
- Secret for database credentials.
- Headless or normal Service for internal access.
- MySQL StatefulSet.

## Data Flow
1. Kubernetes creates the database namespace and storage objects.
2. The MySQL pod starts with persistent storage attached.
3. The secret provides credentials to the workload.
4. The backend connects to the MySQL service by DNS name.
5. The backend uses that database for the `/api/db-test` health check.

## Implementation Notes
- The role first removes any old MySQL resources from the `default` namespace.
- This keeps the project aligned with the newer namespaced architecture.
- The StatefulSet is used because the database needs stable storage identity.

## Key Files
- `files/namespace.yaml`
- `files/pv.yaml`
- `files/pvc.yaml`
- `files/secret.yaml`
- `files/service.yaml`
- `files/statefulset.yaml`
- `tasks/main.yml`
