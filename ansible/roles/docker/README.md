# Docker Role

## Purpose
This role installs Docker for the services VM and the worker nodes, and configures registry access for the local Nexus registry.

## What It Does
- Installs the Docker engine.
- Starts and enables the Docker service.
- Adds the `vagrant` user to the `docker` group.
- Installs the Python Docker SDK and the `community.docker` Ansible collection on the services VM.
- Configures Docker and containerd to trust the local insecure Nexus registry endpoint.

## Data Flow
1. The services VM runs Gitea and Nexus containers with Docker.
2. Jenkins builds images on Docker-enabled workers or services infrastructure.
3. Docker pushes images to the Nexus registry.
4. Kubernetes nodes pull the same images during deployment rollouts.

## Why It Matters
Without Docker, the services VM cannot host the supporting containers and Jenkins cannot build or push images in the current project design.

## Key Files
- `tasks/main.yml`
- `handlers/main.yml`
