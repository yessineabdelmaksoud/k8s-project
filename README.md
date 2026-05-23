# Kubernetes Cluster - Local Development Environment

## What This Project Is

This repository provisions a complete local platform for learning and testing Kubernetes delivery flows.
It combines infrastructure provisioning, cluster bootstrap, application deployment, and CI/CD in one reproducible setup.

The main idea is simple:
1. Vagrant creates the virtual machines.
2. Ansible configures the operating system and installs Kubernetes.
3. The cluster runs MySQL, backend, frontend, and Jenkins.
4. Jenkins pulls code from Gitea, builds images, pushes them to Nexus, and deploys the apps into Kubernetes.

If you want the deeper architecture diagram, read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Mental Model

Think of the project as four layers:

1. **Infrastructure layer** - Vagrant and VirtualBox create the machines.
2. **Platform layer** - Ansible installs Docker, containerd, kubeadm, kubelet, kubectl, NFS, and supporting services.
3. **Cluster layer** - Kubernetes runs namespaces, services, deployments, StatefulSets, and Jenkins.
4. **Delivery layer** - Jenkins builds and deploys the backend and frontend through Nexus and Gitea.

## Machines

| Node | Hostname | IP | CPU | RAM | Role |
|------|----------|----|-----|-----|------|
| Master | k8s-master | 192.168.56.10 | 2 | 4 GB | Kubernetes control plane |
| Worker 1 | k8s-worker1 | 192.168.56.11 | 2 | 2 GB | Application workload node |
| Worker 2 | k8s-worker2 | 192.168.56.12 | 2 | 2 GB | Application workload node |
| Services | services | 192.168.56.20 | 2 | 4 GB | Docker, Gitea, Nexus, supporting services |

**Base stack:** Ubuntu 22.04, Kubernetes 1.29.2, containerd, Flannel, kubeadm.

## Component Roles

### Vagrant
Vagrant defines the VM topology and triggers provisioning. It is the entry point for the whole environment.

### Ansible
Ansible applies the system configuration in a fixed order. It disables swap, configures kernel settings, installs Kubernetes packages, bootstraps the control plane, joins workers, and deploys the apps.

### Kubernetes
Kubernetes is the runtime. It hosts the namespaces for `database`, `backend`, `frontend`, and `jenkins`.

### Gitea
Gitea stores the source code repositories. Jenkins reads the backend and frontend code from there.

### Nexus
Nexus stores Docker images built by Jenkins. Kubernetes pulls those images during rollout.

### Jenkins
Jenkins runs the CI/CD pipelines. It builds images, pushes them to Nexus, then updates the Kubernetes deployments.

### MySQL
MySQL provides persistent database storage for the backend service.

### Backend
The backend is a Node.js API with a MySQL connection pool and health endpoints used by Kubernetes and the frontend.

### Frontend
The frontend is a React app that checks backend/database availability from the browser and displays status.

## How The Data Flows

### Bootstrap flow
1. `vagrant up` creates the four VMs.
2. Ansible configures the Kubernetes nodes and the services VM.
3. The master initializes the control plane.
4. Workers join the cluster.
5. Flannel enables pod networking.
6. MySQL, Jenkins, backend, and frontend are deployed.

### Delivery flow
1. The developer pushes code to Gitea.
2. Jenkins checks out the repository using the `Jenkinsfile`.
3. Jenkins builds a Docker image.
4. Jenkins logs in to Nexus and pushes the image.
5. Jenkins updates the Kubernetes deployment image tag.
6. Kubernetes pulls the new image and rolls out the update.

### Application flow
1. The browser loads the frontend service.
2. The frontend calls `/api/db-test`.
3. Nginx proxies `/api` to the backend.
4. The backend queries MySQL.
5. The JSON response updates the frontend status display.

## Repository Layout

```
cluster/
├── Vagrantfile
├── ansible/
│   ├── inventory.ini
│   ├── group_vars/all.yml
│   ├── playbook.yml
│   └── roles/
├── app/
│   ├── backend/
│   └── frontend/
├── docs/
│   └── ARCHITECTURE.md
├── scripts/
└── README.md
```

## Prerequisites

Install these tools on the host machine:

- Vagrant 2.3 or newer
- VirtualBox 7.0 or newer
- Ansible 2.14 or newer

Windows note: Ansible runs through Vagrant's Ansible provisioner, so you need a shell where `ansible-playbook` is available, such as WSL or Git Bash.

## Fast Start

### 1. Create the environment

```bash
vagrant up
```

That command does the full bootstrap:
- creates the VMs
- configures the nodes
- initializes Kubernetes
- joins workers
- deploys Flannel
- deploys the applications

### 2. Check the cluster

```bash
vagrant ssh k8s-master -c "kubectl get nodes"
vagrant ssh k8s-master -c "kubectl get pods -A"
```

### 3. Open the services

- Gitea: http://192.168.56.20:3000
- Nexus: http://192.168.56.20:8081
- Jenkins: http://192.168.56.11:32000 or http://192.168.56.12:32000

## What To Expect After Provisioning

- The control plane node should be `Ready`.
- Both workers should be `Ready`.
- The system pods in `kube-system` should be running.
- The `database`, `backend`, `frontend`, and `jenkins` namespaces should exist.
- Jenkins should be reachable through a NodePort service.

## Common Commands

```bash
# Pause the VMs without deleting them
vagrant halt

# Start them again
vagrant up

# Re-run only the Ansible provisioning
vagrant provision

# Remove all VMs and state
vagrant destroy -f

# Check current Vagrant status
vagrant status
```

## Configuration File

The key parameters are in [ansible/group_vars/all.yml](ansible/group_vars/all.yml):

| Variable | Default | Meaning |
|----------|---------|---------|
| `kube_version` | `1.29.2-1.1` | Pinned Kubernetes package version |
| `kube_major_version` | `1.29` | Used for the Kubernetes apt repository |
| `pod_network_cidr` | `10.244.0.0/16` | Flannel pod network CIDR |
| `master_ip` | `192.168.56.10` | Kubernetes API server address |
| `flannel_manifest_url` | `...kube-flannel.yml` | Flannel manifest URL |

## Ansible Execution Order

```
Play 1 - k8s_cluster
  common -> nfs_client -> containerd -> kubernetes

Play 2 - masters
  master -> cni

Play 3 - workers
  workers

Play 4 - validation
  kubectl checks from the master

Play 5 - services
  common -> nfs_server
```

## Design Choices

- Idempotent tasks so the playbook can be re-run safely.
- Kubernetes packages pinned for reproducibility.
- Jenkins configured to use in-cluster Kubernetes access.
- Gitea and Nexus separated on the services VM to keep CI/CD isolated from the cluster nodes.
- NFS used for persistent volumes so storage survives restarts.

## Troubleshooting

```bash
# Verbose provisioning
ANSIBLE_VERBOSITY=3 vagrant provision

# Kubelet logs on the master
vagrant ssh k8s-master -c "sudo journalctl -u kubelet -f"

# Reset a worker if join is broken
vagrant ssh k8s-worker1 -c "sudo kubeadm reset -f"
```

If Jenkins does not deploy correctly, start with the Jenkins role README and then check the pipeline logs.

## Trigger And Test It

The backend and frontend pipelines are intended to be triggered by Gitea webhooks, not by polling.

The Jenkinsfiles stay simple and only define the build steps. The actual trigger is configured in Jenkins and Gitea.

### How to set up the webhook

1. Install the Jenkins plugin for Gitea webhook support. If the plugin is not already installed, add it from Manage Jenkins, Plugins.
2. Open the Jenkins job for backend or frontend.
3. Make sure the job is configured as Pipeline script from SCM and points to the correct Gitea repository and branch main.
4. In the job trigger section, enable the Gitea webhook trigger option if the plugin exposes it.
5. In Gitea, open the target repository, then go to Settings, Webhooks, Add Webhook.
6. Choose Gitea as the webhook type if available.
7. Set the target URL to the Jenkins webhook endpoint exposed by the plugin. For the Gitea plugin, the usual endpoint is http://192.168.56.11:32000/gitea-webhook/post. If you use another plugin, keep the same Jenkins base address and use that plugin's endpoint.
8. Set the content type to JSON.
9. Save the webhook.
10. Use the webhook test button in Gitea to confirm Jenkins responds with success.

### How to test end to end

1. Make a small change in either app/backend or app/frontend.
2. Commit and push the change to the matching Gitea repository.
3. Open Gitea repository settings and check the webhook delivery history.
4. Confirm the delivery returned a successful HTTP status.
5. Open Jenkins and confirm a new build started automatically.
6. Check that the stages Checkout, Build Image, Push to Nexus, Deploy, and Verify all pass.

### Fast manual test

If you want to test immediately, you can push an empty commit from the repository clone on the services VM:

vagrant ssh services -c "cd /home/vagrant/app/backend && git commit --allow-empty -m 'trigger test' && git push origin main"

This is useful to confirm that Jenkins reacts to a new push, even if you do not change application code.

## Go Deeper

- [Architecture overview](docs/ARCHITECTURE.md)
- [Backend service](app/backend/README.md)
- [Frontend service](app/frontend/README.md)
- [Ansible guide](ansible/README.md)

```
cluster
├─ ansible
│  ├─ group_vars
│  │  └─ all.yml
│  ├─ inventory.ini
│  ├─ playbook.yml
│  ├─ README.md
│  └─ roles
│     ├─ backend
│     │  ├─ files
│     │  │  ├─ deployment.yaml
│     │  │  ├─ namespace.yaml
│     │  │  ├─ secret.yaml
│     │  │  └─ service.yaml
│     │  └─ tasks
│     │     └─ main.yml
│     ├─ cni
│     │  ├─ README.md
│     │  └─ tasks
│     │     └─ main.yml
│     ├─ common
│     │  ├─ handlers
│     │  │  └─ main.yml
│     │  ├─ README.md
│     │  └─ tasks
│     │     └─ main.yml
│     ├─ containerd
│     │  ├─ handlers
│     │  │  └─ main.yml
│     │  ├─ README.md
│     │  └─ tasks
│     │     └─ main.yml
│     ├─ docker
│     │  ├─ handlers
│     │  │  └─ main.yml
│     │  ├─ README.md
│     │  └─ tasks
│     │     └─ main.yml
│     ├─ frontend
│     │  ├─ files
│     │  │  ├─ deployment.yaml
│     │  │  ├─ namespace.yaml
│     │  │  └─ service.yaml
│     │  └─ tasks
│     │     └─ main.yml
│     ├─ gitea
│     │  ├─ README.md
│     │  └─ tasks
│     │     └─ main.yml
│     ├─ ingress
│     │  ├─ files
│     │  │  ├─ app-ingress.yaml
│     │  │  └─ backend-alias.yaml
│     │  └─ tasks
│     │     └─ main.yml
│     ├─ jenkins
│     │  ├─ files
│     │  │  ├─ deployment.yaml
│     │  │  ├─ namespace.yaml
│     │  │  ├─ pv.yaml
│     │  │  ├─ pvc.yaml
│     │  │  ├─ service.yaml
│     │  │  └─ serviceaccount.yaml
│     │  ├─ README.md
│     │  └─ tasks
│     │     └─ main.yml
│     ├─ kubernetes
│     │  ├─ README.md
│     │  └─ tasks
│     │     └─ main.yml
│     ├─ master
│     │  ├─ README.md
│     │  └─ tasks
│     │     └─ main.yml
│     ├─ mysql
│     │  ├─ files
│     │  │  ├─ namespace.yaml
│     │  │  ├─ pv.yaml
│     │  │  ├─ pvc.yaml
│     │  │  ├─ secret.yaml
│     │  │  ├─ service.yaml
│     │  │  └─ statefulset.yaml
│     │  ├─ README.md
│     │  └─ tasks
│     │     └─ main.yml
│     ├─ nexus
│     │  ├─ README.md
│     │  └─ tasks
│     │     └─ main.yml
│     ├─ nfs_client
│     │  ├─ README.md
│     │  └─ tasks
│     │     └─ main.yml
│     ├─ nfs_server
│     │  ├─ handlers
│     │  │  └─ main.yml
│     │  ├─ README.md
│     │  └─ tasks
│     │     └─ main.yml
│     ├─ vault
│     │  ├─ files
│     │  │  └─ vault.hcl
│     │  └─ tasks
│     │     └─ main.yml
│     └─ workers
│        ├─ README.md
│        └─ tasks
│           └─ main.yml
├─ app
│  ├─ backend
│  │  ├─ Dockerfile
│  │  ├─ Jenkinsfile
│  │  ├─ package.json
│  │  ├─ README.md
│  │  └─ server.js
│  └─ frontend
│     ├─ Dockerfile
│     ├─ index.html
│     ├─ Jenkinsfile
│     ├─ nginx.conf
│     ├─ package.json
│     ├─ README.md
│     ├─ src
│     │  ├─ App.jsx
│     │  └─ main.jsx
│     └─ vite.config.js
├─ docs
│  ├─ ARCHITECTURE.md
│  ├─ DOCUMENTATION.md
│  ├─ IMPLEMENTATION_TECHNIQUE_STAGE1.md
│  ├─ IMPLEMENTATION_TECHNIQUE_STAGE3.md
│  ├─ README_DEMO.md
│  └─ STAGE2_DOCUMENTATION.md
├─ fix_jenkins_config.sh
├─ fix_pull_secrets.sh
├─ infra
│  ├─ ansible
│  │  └─ group_vars
│  │     └─ vault.yml
│  ├─ group_vars
│  │  └─ vault.yml.example
│  ├─ README.md
│  └─ scripts
│     ├─ bootstrap_repo.ps1
│     └─ bootstrap_repo.sh
├─ README.md
├─ run.md
├─ scripts
│  ├─ jenkins-kubectl-setup.sh
│  └─ nexus-setup.sh
├─ tmp_fix.sh
└─ Vagrantfile

```