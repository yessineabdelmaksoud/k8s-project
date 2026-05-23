# Kubernetes DevOps Project Demo — Vagrant + Ansible + Kubernetes + Jenkins + Gitea + Nexus + Ingress

## 1. Goal of the project

This project demonstrates a complete local DevOps platform using 4 VirtualBox VMs managed by Vagrant:

- `k8s-master` — Kubernetes control plane
- `k8s-worker1` — Kubernetes worker node
- `k8s-worker2` — Kubernetes worker node
- `services` — DevOps services VM: Gitea, Nexus, NFS, Ansible execution point

The final application flow is:

```text
Developer pushes code to Gitea
        ↓
Jenkins pipeline builds Docker image
        ↓
Jenkins pushes image to Nexus registry
        ↓
Jenkins deploys to Kubernetes
        ↓
Kubernetes runs backend/frontend pods
        ↓
Ingress exposes the application using one host
```

---

## 2. Architecture summary

```text
Windows Host
│
├── VirtualBox + Vagrant
│
├── services VM — 192.168.56.20
│   ├── Gitea        :3000
│   ├── Nexus UI     :8081
│   ├── Nexus Docker :8082
│   ├── NFS server   /srv/nfs/k8s
│   └── Ansible execution node
│
└── Kubernetes Cluster
    ├── k8s-master  — 192.168.56.10
    ├── k8s-worker1 — 192.168.56.11
    └── k8s-worker2 — 192.168.56.12

Kubernetes namespaces:
- database
- backend
- frontend
- jenkins
- ingress-nginx
```

---

## 3. Component roles

| Component | Role |
|---|---|
| Vagrant | Creates and starts the 4 VMs |
| VirtualBox | Runs the VMs locally |
| Ansible | Installs and configures Kubernetes, Docker, NFS, Gitea, Nexus, Jenkins |
| kubeadm | Initializes the Kubernetes control plane and joins workers |
| containerd | Container runtime used by Kubernetes nodes |
| Flannel | Kubernetes CNI plugin, creates pod network `10.244.0.0/16` |
| Gitea | Private Git server for backend/frontend repositories |
| Nexus | Private Docker registry on `192.168.56.20:8082` |
| Jenkins | CI/CD server: builds, pushes, deploys |
| NFS | Persistent storage backend for MySQL and Jenkins |
| PV/PVC | Kubernetes persistent storage objects |
| MySQL | Database pod with persistent volume |
| Backend | Node.js API exposed on `/api/health` |
| Frontend | Static frontend served by nginx |
| Ingress NGINX | Routes `/` to frontend and `/api` to backend |

---

## 4. Current working URLs

### Direct NodePort access

```text
Frontend:
http://192.168.56.11:30000/

Backend:
http://192.168.56.11:30080/api/health

Jenkins:
http://192.168.56.11:32000/

Gitea:
http://192.168.56.20:3000

Nexus:
http://192.168.56.20:8081

Nexus Docker Registry:
192.168.56.20:8082
```

### Ingress access

Add this to Windows hosts file:

```text
192.168.56.11 k8s-app.local
```

File path:

```text
C:\Windows\System32\drivers\etc\hosts
```

Then use:

```text
Frontend via Ingress:
http://k8s-app.local:30090/

Backend via Ingress:
http://k8s-app.local:30090/api/health
```

---

# 5. Full demo commands for professor

Run these commands from:

```powershell
C:\Users\pc\Desktop\k8s\cluster
```

---

## Step 1 — Show Vagrant VMs

```powershell
vagrant status
```

Expected:

```text
k8s-master     running
k8s-worker1    running
k8s-worker2    running
services       running
```

Explain:

```text
Vagrant manages 4 VMs. Three are for Kubernetes and one is for DevOps services.
```

---

## Step 2 — Show Kubernetes cluster nodes

```powershell
vagrant ssh k8s-master -c "kubectl get nodes -o wide"
```

Expected:

```text
k8s-master    Ready    control-plane
k8s-worker1   Ready
k8s-worker2   Ready
```

Explain:

```text
The master is the control plane. The workers run application pods.
```

---

## Step 3 — Show Kubernetes system pods

```powershell
vagrant ssh k8s-master -c "kubectl get pods -A -o wide"
```

Explain important pods:

```text
kube-system: Kubernetes control plane components
kube-flannel: CNI network pods
database: MySQL
backend: API pods
frontend: web UI pods
jenkins: CI/CD server pod
ingress-nginx: ingress controller
```

---

## Step 4 — Show Flannel CNI

```powershell
vagrant ssh k8s-master -c "kubectl get pods -n kube-flannel -o wide"
```

Expected:

```text
One flannel pod on each node, all 1/1 Running.
```

Explain:

```text
Flannel creates the pod network 10.244.0.0/16 and allows pods on different nodes to communicate.
```

---

## Step 5 — Show services and NodePorts

```powershell
vagrant ssh k8s-master -c "kubectl get svc -A -o wide"
```

Expected important services:

```text
backend    NodePort  8080:30080
frontend   NodePort  80:30000
jenkins    NodePort  8080:32000
mysql-svc  ClusterIP 3306
```

Explain:

```text
NodePort exposes services outside the cluster.
ClusterIP is internal only.
MySQL is internal because only backend should access it.
```

---

## Step 6 — Show backend and frontend deployments

```powershell
vagrant ssh k8s-master -c "kubectl get deployment -n backend"
vagrant ssh k8s-master -c "kubectl get deployment -n frontend"
```

Expected:

```text
backend    2/2 Ready
frontend   2/2 Ready
```

Explain:

```text
Each app has 2 replicas, so Kubernetes runs 2 pods for availability.
```

---

## Step 7 — Show endpoints

```powershell
vagrant ssh k8s-master -c "kubectl get svc,endpoints -n backend -o wide"
vagrant ssh k8s-master -c "kubectl get svc,endpoints -n frontend -o wide"
```

Explain:

```text
The service selects pods using labels.
Endpoints show the real pod IPs behind the service.
```

---

## Step 8 — Test backend and frontend directly

```powershell
vagrant ssh services -c "curl -s http://192.168.56.11:30080/api/health"
vagrant ssh services -c "curl -s -o /dev/null -w '%{http_code}\n' http://192.168.56.11:30000/"
```

Expected:

```text
{"status":"UP","service":"backend-v2"}
200
```

Explain:

```text
This proves the backend and frontend are reachable through Kubernetes NodePort services.
```

---

## Step 9 — Show PV/PVC storage

```powershell
vagrant ssh k8s-master -c "kubectl get pv,pvc -A"
```

Expected:

```text
pv-mysql       Bound   database/pvc-mysql
pv-jenkins     Bound   jenkins/jenkins-pvc
```

Explain:

```text
PV is the real storage resource.
PVC is the claim used by a pod.
MySQL and Jenkins data survive pod restart because they use persistent volumes.
```

---

## Step 10 — Show NFS export from services VM

```powershell
vagrant ssh k8s-master -c "showmount -e 192.168.56.20"
```

Expected:

```text
/srv/nfs/k8s 192.168.56.0/24
```

Explain:

```text
The services VM exports NFS storage to Kubernetes nodes.
```

---

## Step 11 — Show MySQL running

```powershell
vagrant ssh k8s-master -c "kubectl get pods -n database -o wide"
vagrant ssh k8s-master -c "kubectl get svc -n database"
```

Expected:

```text
mysql-0  1/1 Running
mysql-svc ClusterIP
```

Explain:

```text
MySQL is internal and used by the backend through the DNS name mysql-svc.database.svc.cluster.local.
```

Optional database check:

```powershell
vagrant ssh k8s-master -c "kubectl exec -n database mysql-0 -- mysql -uroot -prootpass123 -e 'SHOW DATABASES;'"
```

---

## Step 12 — Show DevOps containers on services VM

```powershell
vagrant ssh services -c "sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'"
```

Expected:

```text
gitea   port 3000
nexus   ports 8081 and 8082
```

Explain:

```text
Gitea stores source code.
Nexus stores Docker images.
Jenkins is deployed inside Kubernetes in the jenkins namespace.
```

---

## Step 13 — Show Nexus registry images

```powershell
vagrant ssh services -c "curl -s -u admin:admin123 http://localhost:8082/v2/_catalog"
vagrant ssh services -c "curl -s -u admin:admin123 http://localhost:8082/v2/backend/tags/list"
vagrant ssh services -c "curl -s -u admin:admin123 http://localhost:8082/v2/frontend/tags/list"
```

Expected:

```json
{"repositories":["backend","frontend"]}
```

Explain:

```text
Jenkins pushes Docker images to Nexus.
Kubernetes workers pull images from Nexus.
```

---

## Step 14 — Show Jenkins can access Kubernetes

```powershell
vagrant ssh k8s-master -c "kubectl exec -n jenkins deployment/jenkins -- kubectl get nodes"
```

Expected:

```text
3 nodes Ready
```

Explain:

```text
Jenkins has kubeconfig, so it can deploy to Kubernetes.
```

---

## Step 15 — Show Jenkins can build Docker images

```powershell
vagrant ssh k8s-master -c "kubectl exec -n jenkins deployment/jenkins -- docker info --format '{{.ServerVersion}}'"
```

Expected:

```text
29.1.3
```

Explain:

```text
Jenkins can use Docker to build images because Docker access is configured.
```

---

# 6. CI/CD demonstration

## Backend demo

### 1. Modify backend code

On services VM:

```bash
cd /home/vagrant/app/backend
sed -i "s/service: 'backend-demo-2'/service: 'backend-demo-3'/" server.js
git diff
git add server.js
git commit -m "demo backend pipeline"
git push origin main
```

### 2. Launch Jenkins job

In Jenkins UI:

```text
backend-pipeline → Build Now
```

### 3. Verify new Nexus tag

```bash
curl -s -u admin:admin123 http://localhost:8082/v2/backend/tags/list
```

Expected:

```text
A new numeric tag appears and latest is updated.
```

### 4. Verify Kubernetes rollout

```bash
kubectl rollout status deployment/backend -n backend
kubectl get pods -n backend -o wide
```

Expected:

```text
deployment "backend" successfully rolled out
backend pods 1/1 Running
```

### 5. Verify backend result

```bash
curl -s http://192.168.56.11:30080/api/health
```

Expected:

```json
{"status":"UP","service":"backend-demo"}
```

---

## Frontend demo

### 1. Modify frontend code

On services VM:

```bash
cd /home/vagrant/app/frontend
grep -R "K8s\|Frontend\|App" -n . | head
```

Edit a visible text, then:

```bash
git diff
git add .
git commit -m "demo frontend pipeline"
git push origin main
```

### 2. Launch Jenkins job

In Jenkins UI:

```text
frontend-pipeline → Build Now
```

### 3. Verify new Nexus tag

```bash
curl -s -u admin:admin123 http://localhost:8082/v2/frontend/tags/list
```

### 4. Verify Kubernetes rollout

```bash
kubectl rollout status deployment/frontend -n frontend
kubectl get pods -n frontend -o wide
```

### 5. Verify frontend

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.56.11:30000/
```

Expected:

```text
200
```

---

# 7. Ingress demo

## Show Ingress controller

```powershell
vagrant ssh k8s-master -c "kubectl get pods -n ingress-nginx -o wide"
vagrant ssh k8s-master -c "kubectl get svc -n ingress-nginx"
```

Expected:

```text
ingress-nginx-controller 1/1 Running
HTTP exposed on NodePort 30090
```

## Show Ingress rule

```powershell
vagrant ssh k8s-master -c "kubectl get ingress -n frontend"
vagrant ssh k8s-master -c "kubectl describe ingress app-ingress -n frontend"
```

Explain:

```text
Host: k8s-app.local
/    routes to frontend service
/api routes to backend service
```

## Test Ingress

```powershell
vagrant ssh services -c "curl -H 'Host: k8s-app.local' http://192.168.56.11:30090/"
vagrant ssh services -c "curl -H 'Host: k8s-app.local' http://192.168.56.11:30090/api/health"
```

Expected:

```text
Frontend HTML
{"status":"UP","service":"backend-v2"} or current backend service name
```

---

# 9. Vault Demo — Secret Management

## Role of Vault

Vault is used as a centralized secret manager.

Before using Vault, secrets were stored in different places:

```text
Kubernetes Secret     → mysql-secret
Jenkins Credentials   → nexus-credentials
Manual scripts/YAML   → setup credentials
```

With Vault, secrets are stored in one central place:

```text
Vault
├── secret/mysql
├── secret/nexus
└── secret/jenkins
```

In this demo, Vault runs on the **services VM**.

```text
Vault UI: http://192.168.56.20:8201
Token: root
```

> **Important note**
>
> Vault is running in **dev mode** for demonstration.
>
> Storage type is **in-memory**.
>
> For production, we need:
>
> - persistent storage
> - Vault policies
> - Kubernetes Auth or AppRole
> - a real unseal process

---

## 1. Show Vault Container

Run this command from your project folder:

```bash
vagrant ssh services -c "sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}' | grep vault"
```

Expected output:

```text
vault   hashicorp/vault:1.17   0.0.0.0:8201->8200/tcp
```

Explanation:

Vault is running as a Docker container on the **services VM**.

Port `8201` on the services VM is mapped to port `8200` inside the Vault container.

---

## 2. Show Vault Health

Run:

```bash
vagrant ssh services -c "curl -s http://localhost:8201/v1/sys/health"
```

Expected output:

```json
{"initialized":true,"sealed":false}
```

Explanation:

```text
initialized=true  → Vault is initialized
sealed=false      → Vault is unsealed and usable
```

---

## 3. Show Vault Status

Run:

```bash
vagrant ssh services -c "sudo docker exec vault sh -c 'export VAULT_ADDR=http://127.0.0.1:8200; export VAULT_TOKEN=root; vault status'"
```

Expected output:

```text
Initialized     true
Sealed          false
Storage Type    inmem
```

Explanation:

Vault is operational.

In this local demo, the storage type is **in-memory**.

This means Vault data is stored in memory only.

---

## 4. Show MySQL Secret in Vault

Run:

```bash
vagrant ssh services -c "sudo docker exec vault sh -c 'export VAULT_ADDR=http://127.0.0.1:8200; export VAULT_TOKEN=root; vault kv get secret/mysql'"
```

Expected output:

```text
DB_HOST        mysql-svc.database.svc.cluster.local
DB_NAME        appdb
DB_PASSWORD    apppass123
DB_PORT        3306
DB_USER        appuser
```

Explanation:

These are the database credentials.

They can be centralized in Vault instead of being stored only in Kubernetes Secrets.

Vault path:

```text
secret/mysql
```

---

## 5. Show Nexus Secret in Vault

Run:

```bash
vagrant ssh services -c "sudo docker exec vault sh -c 'export VAULT_ADDR=http://127.0.0.1:8200; export VAULT_TOKEN=root; vault kv get secret/nexus'"
```

Expected output:

```text
username    admin
password    admin123
registry    192.168.56.20:8082
```

Explanation:

These credentials are used by Jenkins and Docker to authenticate with the Nexus Docker registry.

Vault path:

```text
secret/nexus
```

---

## 6. Show Jenkins Note Secret

Run:

```bash
vagrant ssh services -c "sudo docker exec vault sh -c 'export VAULT_ADDR=http://127.0.0.1:8200; export VAULT_TOKEN=root; vault kv get secret/jenkins'"
```

Expected output:

```text
Jenkins can retrieve secrets from Vault in the next improvement
```

Explanation:

This demonstrates that Vault is ready to be integrated with Jenkins pipelines.

Vault path:

```text
secret/jenkins
```

---

## 7. Open Vault UI

Open this URL in your browser:

```text
http://192.168.56.20:8201
```

Login using:

```text
Method: Token
Token: root
```

Show these paths in the Vault UI:

```text
secret/mysql
secret/nexus
secret/jenkins
```

---

## Demo Summary

In this demo, Vault centralizes application and infrastructure secrets.

Before Vault:

```text
Kubernetes Secret
Jenkins Credentials
Manual YAML/scripts
```

After Vault:

```text
Vault
├── secret/mysql
├── secret/nexus
└── secret/jenkins
```

Vault provides one central place to manage secrets.

For this local demo:

```text
Vault mode      → dev mode
Token           → root
Storage type    → in-memory
Vault UI        → http://192.168.56.20:8201
```

# 8. Important implementation fixes made

## Nexus registry port

Nexus must be created with both ports:

```bash
-p 8081:8081 -p 8082:8082 -v /srv/nexus:/nexus-data
```

Why:

```text
8081 = Nexus UI
8082 = Docker Registry API
```

Without `8082`, Kubernetes fails with:

```text
connect: connection refused
```

## Image pull secret

Backend and frontend namespaces need Docker registry credentials:

```bash
kubectl create secret docker-registry nexus-regcred \
  --docker-server=192.168.56.20:8082 \
  --docker-username=admin \
  --docker-password=admin123 \
  -n backend
```

Same for frontend.

Deployments must contain:

```yaml
imagePullSecrets:
  - name: nexus-regcred
```

Without this, Kubernetes fails with:

```text
authorization failed: no basic auth credentials
```

## Ingress rewrite fix

Backend expects:

```text
/api/health
```

So Ingress must not rewrite `/api/health` to `/health`.

Correct rule:

```yaml
- path: /api
  pathType: Prefix
  backend:
    service:
      name: backend
      port:
        number: 8080
```

---

# 9. Final validation checklist

Before presenting, run:

```powershell
vagrant status
vagrant ssh k8s-master -c "kubectl get nodes -o wide"
vagrant ssh k8s-master -c "kubectl get pods -A -o wide"
vagrant ssh k8s-master -c "kubectl get svc -A -o wide"
vagrant ssh k8s-master -c "kubectl get ingress -A"
vagrant ssh k8s-master -c "kubectl get pv,pvc -A"
vagrant ssh services -c "sudo docker ps"
vagrant ssh services -c "curl -s -u admin:admin123 http://localhost:8082/v2/_catalog"
vagrant ssh services -c "curl -s http://192.168.56.11:30080/api/health"
vagrant ssh services -c "curl -s -o /dev/null -w '%{http_code}\n' http://192.168.56.11:30000/"
vagrant ssh services -c "curl -H 'Host: k8s-app.local' http://192.168.56.11:30090/api/health"
```

If all these commands work, the project is ready to present.

---

# 10. Short oral explanation

```text
I built a complete local DevOps environment using Vagrant and VirtualBox.
The cluster has one master and two workers. Ansible provisions Kubernetes with kubeadm, containerd, and Flannel.
The services VM hosts Gitea for Git, Nexus for Docker images, and NFS for persistent storage.
MySQL runs in Kubernetes with a PVC backed by NFS.
The backend and frontend are containerized and deployed as Kubernetes deployments with two replicas each.
Jenkins builds the Docker images, pushes them to Nexus, and deploys them to Kubernetes.
Finally, Ingress NGINX exposes the application through one host: k8s-app.local.
```