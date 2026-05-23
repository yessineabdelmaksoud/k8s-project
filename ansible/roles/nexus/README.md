# Nexus Role

## Purpose
This role deploys Nexus Repository Manager on the `services` VM to host Docker images for the backend and frontend pipelines.

## What It Provides
- A persistent `/srv/nexus` data directory.
- A Nexus container.
- Web access on port `8081`.
- Docker registry access through the configured registry port in the environment.

## Data Flow
1. Jenkins builds a container image locally.
2. Jenkins logs in to Nexus using stored credentials.
3. Jenkins pushes versioned and `latest` tags to Nexus.
4. Kubernetes deployments pull the new image tag from Nexus during rollout.

## Implementation Notes
- The role waits until Nexus responds on HTTP before continuing.
- Directory ownership is set to the Nexus container UID/GID requirements.

## Key File
- `tasks/main.yml`
