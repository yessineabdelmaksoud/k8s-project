# Gitea Role

## Purpose
This role deploys Gitea on the `services` VM so the project has a local Git hosting server for Jenkins SCM checkouts.

## What It Provides
- A persistent `/srv/gitea` data directory.
- A Gitea container.
- HTTP access on port `3000`.
- SSH access on port `2222` if needed.

## Data Flow
1. Developers push the backend and frontend code to Gitea.
2. Jenkins pulls the repository from Gitea using the pipeline SCM configuration.
3. Jenkins uses the checked-out source to build Docker images.

## Implementation Notes
- The role uses the Docker container module instead of raw shell commands.
- Data is persisted on the host filesystem so repository state survives restarts.

## Key File
- `tasks/main.yml`
