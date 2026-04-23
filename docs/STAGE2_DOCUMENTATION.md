# Stage 2 — Persistent Storage & MySQL Deployment

## Overview

This stage adds NFS-based persistent storage to the Kubernetes cluster and deploys MySQL with a PersistentVolume backed by the NFS server running on the `services` VM.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                        │
│                                                                  │
│  ┌─────────────────┐    PVC/PV     ┌─────────────────────────┐  │
│  │   k8s-worker2   │ ◄──────────── │   pv-mysql (5Gi NFS)    │  │
│  │                 │               └────────────┬────────────┘  │
│  │  mysql Pod      │                            │ NFS mount      │
│  │  (Running)      │                            │                │
│  └─────────────────┘               ┌────────────▼────────────┐  │
│                                    │   services VM            │  │
│                                    │   192.168.56.20          │  │
│                                    │   /srv/nfs/k8s           │  │
│                                    │   nfs-kernel-server      │  │
│                                    └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

MySQL Pod
   ↓
PVC (pvc-mysql)
   ↓
PV (pv-mysql)
   ↓
NFS (services VM)
   ↓
/srv/nfs/k8s

---

## Components Added

| Component | Type | Description |
|-----------|------|-------------|
| `nfs_server` | Ansible Role | Installs and configures NFS server on `services` VM |
| `nfs_client` | Ansible Role | Installs `nfs-common` on all K8s nodes |
| `pv-mysql` | PersistentVolume | 5Gi NFS-backed volume, ReclaimPolicy=Retain |
| `pvc-mysql` | PersistentVolumeClaim | Claims pv-mysql, bound to MySQL deployment |
| `mysql-secret` | K8s Secret | Stores DB credentials |
| `mysql` | Deployment | MySQL 8.0, 1 replica, data persisted on NFS |
| `mysql-svc` | Service (ClusterIP) | Internal access to MySQL on port 3306 |

---

## File Structure

```
cluster/
├── ansible/
│   └── roles/
│       ├── nfs_server/
│       │   ├── tasks/main.yml
│       │   └── handlers/main.yml
│       └── nfs_client/
│           └── tasks/main.yml
└── k8s/
    ├── storage/
    │   └── pv-mysql.yml
    └── mysql/
        └── mysql-deployment.yml
```

---

## Ansible Roles

### nfs_server (runs on: services)

`ansible/roles/nfs_server/tasks/main.yml`:
```yaml
---
- name: Install nfs-kernel-server
  ansible.builtin.apt:
    name: nfs-kernel-server
    state: present
    update_cache: true

- name: Create NFS export directory
  ansible.builtin.file:
    path: /srv/nfs/k8s
    state: directory
    mode: "0777"
    owner: nobody
    group: nogroup

- name: Configure NFS exports
  ansible.builtin.lineinfile:
    path: /etc/exports
    line: "/srv/nfs/k8s 192.168.56.0/24(rw,sync,no_subtree_check,no_root_squash)"
    create: true
    mode: "0644"
  notify: reload exports

- name: Enable and start nfs-kernel-server
  ansible.builtin.systemd:
    name: nfs-kernel-server
    enabled: true
    state: started
```

`ansible/roles/nfs_server/handlers/main.yml`:
```yaml
---
- name: reload exports
  ansible.builtin.command: exportfs -ra
  changed_when: true
```

### nfs_client (runs on: k8s_cluster)

`ansible/roles/nfs_client/tasks/main.yml`:
```yaml
---
- name: Stop unattended-upgrades to avoid apt lock
  ansible.builtin.systemd:
    name: unattended-upgrades
    state: stopped
  ignore_errors: true

- name: Install nfs-common on Kubernetes nodes
  ansible.builtin.apt:
    name: nfs-common
    state: present
    update_cache: true
```

### playbook.yml — Updated Play 1 and Play 5

```yaml
- name: Prepare Kubernetes nodes
  hosts: k8s_cluster
  become: true
  roles:
    - role: common
    - role: nfs_client      # ← added
    - role: containerd
    - role: kubernetes

- name: Prepare services node
  hosts: services
  become: true
  roles:
    - role: common
    - role: nfs_server      # ← added
```

---

## Kubernetes Manifests

### pv-mysql.yml

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-mysql
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  nfs:
    server: 192.168.56.20
    path: /srv/nfs/k8s
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-mysql
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

### mysql-deployment.yml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
        - name: mysql
          image: mysql:8.0
          envFrom:
            - secretRef:
                name: mysql-secret
          ports:
            - containerPort: 3306
          volumeMounts:
            - name: mysql-storage
              mountPath: /var/lib/mysql
      volumes:
        - name: mysql-storage
          persistentVolumeClaim:
            claimName: pvc-mysql
---
apiVersion: v1
kind: Service
metadata:
  name: mysql-svc
spec:
  type: ClusterIP
  selector:
    app: mysql
  ports:
    - port: 3306
      targetPort: 3306
```

---

## Deployment Procedure

### Automated (vagrant up)

After adding the Ansible roles and updating `playbook.yml`, a full `vagrant up` handles everything end-to-end.

### Manual Apply (existing cluster)

```bash
# 1. Upload updated Ansible roles to services VM
vagrant upload ansible/roles/nfs_server/tasks/main.yml \
  /home/vagrant/ansible/roles/nfs_server/tasks/main.yml services
vagrant upload ansible/roles/nfs_server/handlers/main.yml \
  /home/vagrant/ansible/roles/nfs_server/handlers/main.yml services
vagrant upload ansible/roles/nfs_client/tasks/main.yml \
  /home/vagrant/ansible/roles/nfs_client/tasks/main.yml services
vagrant upload ansible/playbook.yml \
  /home/vagrant/ansible/playbook.yml services

# 2. Run Ansible on services VM only
vagrant ssh services -c "cd /home/vagrant/ansible && \
  ANSIBLE_HOST_KEY_CHECKING=false \
  ansible-playbook -i inventory.ini playbook.yml --become --limit services"

# 3. Install nfs-common on K8s nodes (if not done via Ansible)
vagrant ssh k8s-master  -c "sudo apt-get install -y nfs-common"
vagrant ssh k8s-worker1 -c "sudo apt-get install -y nfs-common"
vagrant ssh k8s-worker2 -c "sudo apt-get install -y nfs-common"

# 4. Apply storage manifests on master
vagrant ssh k8s-master -c "kubectl apply -f /home/vagrant/pv-mysql.yml"

# 5. Create MySQL secret
vagrant ssh k8s-master -c "kubectl create secret generic mysql-secret \
  --from-literal=MYSQL_ROOT_PASSWORD='rootpass123' \
  --from-literal=MYSQL_DATABASE='appdb' \
  --from-literal=MYSQL_USER='appuser' \
  --from-literal=MYSQL_PASSWORD='apppass123'"

# 6. Deploy MySQL
vagrant ssh k8s-master -c "kubectl apply -f /home/vagrant/mysql-deployment.yml"
```

---

## Issues Encountered & Fixes

### 1. PV status Pending

**Cause:** NFS server not installed on services VM — role `nfs_server` was missing from playbook.

**Fix:** Created `nfs_server` Ansible role and added it to Play 5 in `playbook.yml`.

### 2. Mount failed — bad option

**Cause:** `nfs-common` not installed on worker nodes (apt was locked by `unattended-upgrades` during provisioning).

**Fix:** Added `stop unattended-upgrades` task at the top of `nfs_client` role. Installed `nfs-common` manually as immediate fix.

### 3. MySQL CrashLoopBackOff

**Cause:** NFS directory `/srv/nfs/k8s` contained corrupted InnoDB redo log files from previous failed pod starts.

**Fix:**
```bash
vagrant ssh services -c "sudo rm -rf /srv/nfs/k8s/* && \
  sudo chown -R 999:999 /srv/nfs/k8s && \
  sudo chmod 777 /srv/nfs/k8s"
vagrant ssh k8s-master -c "kubectl rollout restart deployment/mysql"
```

### 4. kubectl get pv pvc — wrong syntax

**Cause:** Space between resource types is invalid.

**Fix:** Use comma: `kubectl get pv,pvc`

---

## Verification Commands

```bash
# NFS export visible from master
vagrant ssh k8s-master -c "showmount -e 192.168.56.20"
# Expected: /srv/nfs/k8s 192.168.56.0/24

# PV and PVC status
vagrant ssh k8s-master -c "kubectl get pv,pvc"
# Expected: pv-mysql Bound, pvc-mysql Bound

# MySQL pod running
vagrant ssh k8s-master -c "kubectl get pods -l app=mysql"
# Expected: mysql-xxxxx 1/1 Running

# MySQL connectivity
vagrant ssh k8s-master -c "MYSQL_POD=\$(kubectl get pods -l app=mysql \
  -o jsonpath='{.items[0].metadata.name}') && \
  kubectl exec -it \$MYSQL_POD -- mysql -uroot -prootpass123 -e 'SHOW DATABASES;'"
# Expected: appdb listed in databases

# Data persists after pod restart
vagrant ssh k8s-master -c "kubectl delete pod -l app=mysql"
vagrant ssh k8s-master -c "kubectl get pods -l app=mysql -w"
# Pod restarts, mounts same NFS volume, data intact
```

---

## Network & Storage Summary

| Network | CIDR | Purpose |
|---------|------|---------|
| Host-Only | 192.168.56.0/24 | VM-to-VM communication |
| Pod Network | 10.244.0.0/16 | Flannel overlay |
| Service Network | 10.96.0.0/12 | ClusterIP virtual IPs |
| NFS Export | 192.168.56.20:/srv/nfs/k8s | Persistent storage |

| Storage Object | Value |
|----------------|-------|
| PV Name | pv-mysql |
| PV Capacity | 5Gi |
| Access Mode | ReadWriteOnce |
| Reclaim Policy | Retain |
| NFS Server | 192.168.56.20 |
| NFS Path | /srv/nfs/k8s |
| MySQL UID | 999 (mysql user inside container) |
