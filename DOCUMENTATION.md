# Kubernetes Cluster — Documentation Complète

## Table des Matières

1. [Vue d'ensemble de l'Architecture](#1-vue-densemble-de-larchitecture)
2. [Qu'est-ce que Kubernetes ?](#2-quest-ce-que-kubernetes-)
3. [Les Composants de Kubernetes](#3-les-composants-de-kubernetes)
4. [Notre Infrastructure (VMs)](#4-notre-infrastructure-vms)
5. [Comment ça marche : le Flux de Provisioning](#5-comment-ça-marche--le-flux-de-provisioning)
6. [Explication Fichier par Fichier](#6-explication-fichier-par-fichier)
7. [Le Réseau dans notre Cluster](#7-le-réseau-dans-notre-cluster)
8. [Commandes Essentielles à Connaître](#8-commandes-essentielles-à-connaître)
9. [Guide de Vérification du Cluster](#9-guide-de-vérification-du-cluster)
10. [Dépannage (Troubleshooting)](#10-dépannage-troubleshooting)

---

## 1. Vue d'ensemble de l'Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        MACHINE HÔTE (Windows)                          │
│                        VirtualBox + Vagrant                            │
│                                                                        │
│  ┌──────────────────── Réseau Host-Only: 192.168.56.0/24 ────────────┐ │
│  │                                                                    │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐   │ │
│  │  │   k8s-master    │  │  k8s-worker1    │  │  k8s-worker2    │   │ │
│  │  │ 192.168.56.10   │  │ 192.168.56.11   │  │ 192.168.56.12   │   │ │
│  │  │ 2 CPU / 4 GB    │  │ 2 CPU / 2 GB    │  │ 2 CPU / 2 GB    │   │ │
│  │  │                 │  │                 │  │                 │   │ │
│  │  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │   │ │
│  │  │ │ API Server  │ │  │ │   kubelet   │ │  │ │   kubelet   │ │   │ │
│  │  │ │ etcd        │ │  │ │ kube-proxy  │ │  │ │ kube-proxy  │ │   │ │
│  │  │ │ scheduler   │ │  │ │ containerd  │ │  │ │ containerd  │ │   │ │
│  │  │ │ controller  │ │  │ │ flannel     │ │  │ │ flannel     │ │   │ │
│  │  │ │ kubelet     │ │  │ └─────────────┘ │  │ └─────────────┘ │   │ │
│  │  │ │ kube-proxy  │ │  │                 │  │                 │   │ │
│  │  │ │ containerd  │ │  │  Exécute les    │  │  Exécute les    │   │ │
│  │  │ │ flannel     │ │  │  Pods/Containers│  │  Pods/Containers│   │ │
│  │  │ │ CoreDNS     │ │  │                 │  │                 │   │ │
│  │  │ └─────────────┘ │  └─────────────────┘  └─────────────────┘   │ │
│  │  └─────────────────┘                                              │ │
│  │                                                                    │ │
│  │  ┌─────────────────┐                                              │ │
│  │  │    services     │  ← VM d'administration / Ansible controller  │ │
│  │  │ 192.168.56.20   │                                              │ │
│  │  │ 2 CPU / 4 GB    │                                              │ │
│  │  └─────────────────┘                                              │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

**4 VMs au total :**
| VM | IP | CPU | RAM | Rôle |
|----|-----|-----|-----|------|
| `k8s-master` | 192.168.56.10 | 2 | 4 Go | Control plane Kubernetes |
| `k8s-worker1` | 192.168.56.11 | 2 | 2 Go | Noeud worker (exécute les Pods) |
| `k8s-worker2` | 192.168.56.12 | 2 | 2 Go | Noeud worker (exécute les Pods) |
| `services` | 192.168.56.20 | 2 | 4 Go | Administration, Ansible, futur CI/CD |

---

## 2. Qu'est-ce que Kubernetes ?

**Kubernetes (K8s)** est un orchestrateur de conteneurs. Il gère automatiquement :

- **Le déploiement** : lance tes applications dans des conteneurs
- **La mise à l'échelle** : augmente/diminue le nombre d'instances
- **La haute disponibilité** : redémarre les conteneurs en cas de crash
- **Le load balancing** : répartit le trafic entre les instances
- **Le réseau** : permet aux conteneurs de communiquer entre eux

### Analogie simple :
> Imagine un chef d'orchestre (Kubernetes) qui dirige des musiciens (conteneurs).
> Le chef décide qui joue quoi, quand, et remplace un musicien absent automatiquement.

### Concepts clés :

| Concept | Description |
|---------|-------------|
| **Pod** | Plus petite unité dans K8s. Contient 1 ou plusieurs conteneurs. |
| **Node** | Une machine (VM) qui exécute des Pods. |
| **Deployment** | Décrit combien de copies d'un Pod tu veux. K8s maintient ce nombre. |
| **Service** | Point d'accès réseau stable vers un groupe de Pods (load balancer interne). |
| **Namespace** | Isolation logique — séparer les environnements (ex: `kube-system`, `default`). |
| **DaemonSet** | Garantit qu'un Pod tourne sur CHAQUE noeud (ex: Flannel, kube-proxy). |
| **ConfigMap/Secret** | Stocker la configuration et les données sensibles. |

---

## 3. Les Composants de Kubernetes

### 3.1 Control Plane (k8s-master)

Le **cerveau** du cluster. Il prend toutes les décisions.

```
┌─────────────────────────────────────────────────┐
│              Control Plane (Master)              │
│                                                  │
│  ┌──────────────┐     ┌──────────────────────┐  │
│  │  API Server   │ ◄──│  kubectl (toi/admin)  │  │
│  │  (kube-apiserver)│  └──────────────────────┘  │
│  └──────┬───────┘                                │
│         │                                        │
│  ┌──────▼───────┐  ┌─────────────┐              │
│  │   etcd        │  │  Scheduler  │              │
│  │ (base de     │  │ (choisit le │              │
│  │  données)    │  │  noeud pour  │              │
│  └──────────────┘  │  chaque Pod) │              │
│                     └─────────────┘              │
│  ┌─────────────────────────────┐                │
│  │  Controller Manager          │                │
│  │  (surveille l'état désiré   │                │
│  │   vs l'état actuel)         │                │
│  └─────────────────────────────┘                │
└─────────────────────────────────────────────────┘
```

| Composant | Rôle |
|-----------|------|
| **kube-apiserver** | Point d'entrée de TOUTES les commandes. `kubectl` communique avec lui. |
| **etcd** | Base de données clé-valeur. Stocke tout l'état du cluster. |
| **kube-scheduler** | Décide sur quel noeud placer un nouveau Pod (selon CPU, RAM, etc.). |
| **kube-controller-manager** | Boucle de contrôle : vérifie en permanence que l'état actuel = l'état désiré. |

### 3.2 Worker Nodes (k8s-worker1, k8s-worker2)

Les **muscles** du cluster. Ils exécutent les conteneurs.

| Composant | Rôle |
|-----------|------|
| **kubelet** | Agent sur chaque noeud. Reçoit les ordres de l'API Server et gère les conteneurs locaux. |
| **kube-proxy** | Gère les règles réseau (iptables). Route le trafic vers les bons Pods. |
| **containerd** | Runtime de conteneurs. Télécharge les images et lance les conteneurs. |

### 3.3 Composants Réseau (Add-ons)

| Composant | Rôle |
|-----------|------|
| **Flannel** | CNI (Container Network Interface). Crée un réseau overlay pour que les Pods communiquent entre noeuds. |
| **CoreDNS** | Service DNS interne. Résout les noms des Services (ex: `nginx-svc.default.svc.cluster.local` → IP). |

---

## 4. Notre Infrastructure (VMs)

### 4.1 Vagrant

**Vagrant** automatise la création des VMs. Un seul fichier (`Vagrantfile`) définit les 4 VMs.

```
vagrant up       →  Crée et démarre les 4 VMs
vagrant halt     →  Arrête les VMs (sans les supprimer)
vagrant destroy  →  Supprime complètement les VMs
vagrant ssh <vm> →  Se connecter en SSH à une VM
```

### 4.2 Ansible

**Ansible** automatise la configuration. Depuis la VM `services`, il se connecte en SSH aux 3 noeuds K8s et exécute toutes les tâches nécessaires.

```
Pourquoi depuis la VM services ?
→ Windows ne supporte pas Ansible nativement.
→ La VM services installe Ansible via pip, puis exécute le playbook.
```

### 4.3 Réseau

Chaque VM a **2 interfaces réseau** :

| Interface | Type | Adresse | Usage |
|-----------|------|---------|-------|
| `enp0s3` | NAT | 10.0.2.15 | Accès Internet (identique pour toutes les VMs) |
| `enp0s8` | Host-Only | 192.168.56.x | Communication entre VMs (unique par VM) |

**Important** : Flannel est configuré avec `--iface=enp0s8` pour utiliser le réseau host-only (et non le NAT).

### 4.4 Réseaux IP

```
192.168.56.0/24   →  Réseau des VMs (host-only, communication entre VMs)
10.244.0.0/16     →  Réseau des Pods (overlay géré par Flannel)
10.96.0.0/12      →  Réseau des Services (ClusterIP virtuel, géré par kube-proxy)
```

---

## 5. Comment ça marche : le Flux de Provisioning

Quand tu tapes `vagrant up`, voici exactement ce qui se passe :

```
vagrant up
  │
  ├── 1. VirtualBox crée 4 VMs (Ubuntu 22.04)
  │     k8s-master  → 192.168.56.10
  │     k8s-worker1 → 192.168.56.11
  │     k8s-worker2 → 192.168.56.12
  │     services    → 192.168.56.20
  │
  ├── 2. Quand la VM "services" démarre (la dernière) :
  │     ├── Upload du dossier ansible/ → /home/vagrant/ansible/
  │     ├── Upload de la clé SSH → /home/vagrant/.ssh/vagrant_rsa
  │     └── Exécution du shell provisioner :
  │           ├── apt install python3-pip
  │           ├── pip3 install ansible
  │           └── ansible-playbook playbook.yml
  │
  ├── 3. Play 1 — Préparation (sur k8s-master, worker1, worker2) :
  │     ├── Role: common
  │     │     ├── Désactiver le swap (/etc/fstab + swapoff -a)
  │     │     ├── Charger modules noyau (overlay, br_netfilter)
  │     │     ├── Configurer sysctl (ip_forward, bridge-nf-call)
  │     │     ├── Installer packages requis (curl, gnupg, etc.)
  │     │     └── Ajouter les entrées /etc/hosts
  │     │
  │     ├── Role: containerd
  │     │     ├── Installer containerd
  │     │     ├── Générer config par défaut
  │     │     ├── Activer SystemdCgroup = true
  │     │     └── Démarrer le service
  │     │
  │     └── Role: kubernetes
  │           ├── Ajouter le dépôt APT Kubernetes (pkgs.k8s.io)
  │           ├── Installer kubelet, kubeadm, kubectl (v1.29.2)
  │           ├── Bloquer les versions (dpkg hold)
  │           └── Activer kubelet
  │
  ├── 4. Play 2 — Initialisation Master (sur k8s-master uniquement) :
  │     ├── Role: master
  │     │     ├── kubeadm init (crée le cluster)
  │     │     ├── Configurer kubectl pour l'utilisateur vagrant
  │     │     └── Générer le join command (token + hash)
  │     │
  │     └── Role: cni
  │           ├── Télécharger le manifest Flannel
  │           ├── Patcher avec --iface=enp0s8
  │           ├── kubectl apply le manifest
  │           └── Attendre que Flannel soit prêt
  │
  ├── 5. Play 3 — Joindre les Workers (sur worker1, worker2) :
  │     └── Role: workers
  │           ├── Vérifier si déjà joint
  │           └── kubeadm join <master-ip>:6443 --token ... --discovery-token-ca-cert-hash ...
  │
  └── 6. Play 4 — Validation (sur k8s-master) :
        ├── Attendre que tous les noeuds soient Ready
        ├── Afficher kubectl get nodes
        └── Afficher kubectl get pods -A
```

---

## 6. Explication Fichier par Fichier

### Structure du Projet

```
cluster/
├── Vagrantfile                          # Définition des 4 VMs
├── DOCUMENTATION.md                     # Ce fichier
│
└── ansible/
    ├── inventory.ini                    # Liste des machines et connexions SSH
    ├── playbook.yml                     # Orchestration : quel rôle sur quelle machine
    │
    ├── group_vars/
    │   └── all.yml                      # Variables partagées (versions, IPs, etc.)
    │
    └── roles/
        ├── common/                      # Prérequis système
        │   ├── tasks/main.yml           #   → swap, modules, sysctl, packages, /etc/hosts
        │   └── handlers/main.yml        #   → handler: sysctl --system
        │
        ├── containerd/                  # Runtime de conteneurs
        │   ├── tasks/main.yml           #   → install, config, SystemdCgroup, start
        │   └── handlers/main.yml        #   → handler: restart containerd
        │
        ├── kubernetes/                  # Paquets K8s
        │   └── tasks/main.yml           #   → repo APT, install, hold, enable kubelet
        │
        ├── master/                      # Initialisation control plane
        │   └── tasks/main.yml           #   → kubeadm init, .kube/config, join command
        │
        ├── cni/                         # Plugin réseau
        │   └── tasks/main.yml           #   → download flannel, patch iface, apply
        │
        └── workers/                     # Jonction des workers
            └── tasks/main.yml           #   → kubeadm join
```

### Vagrantfile — Points Clés

```ruby
# 4 VMs définies dans un tableau
NODES = [
  { name: "k8s-master",  ip: "192.168.56.10", cpus: 2, memory: 4096 },
  { name: "k8s-worker1", ip: "192.168.56.11", cpus: 2, memory: 2048 },
  { name: "k8s-worker2", ip: "192.168.56.12", cpus: 2, memory: 2048 },
  { name: "services",    ip: "192.168.56.20", cpus: 2, memory: 4096 },
]

# Le provisioning ne se fait que sur la DERNIÈRE VM (services)
# → Upload ansible/ et clé SSH, puis pip install ansible + ansible-playbook
```

### inventory.ini — Points Clés

```ini
[masters]            # Groupe : le master
[workers]            # Groupe : les workers
[services]           # Groupe : VM d'admin
[k8s_cluster:children]  # Groupe parent = masters + workers
  masters
  workers
```

### group_vars/all.yml — Variables Importantes

```yaml
kube_version: "1.29.2-1.1"       # Version exacte de K8s
pod_network_cidr: "10.244.0.0/16" # CIDR requis par Flannel
master_ip: "192.168.56.10"        # IP du master (API Server)
```

---

## 7. Le Réseau dans notre Cluster

### 7.1 Pourquoi Désactiver le Swap ?

Kubernetes exige que le swap soit désactivé. Le kubelet refuse de démarrer si le swap est actif.
Raison : K8s gère lui-même la mémoire et le scheduling. Le swap fausserait les calculs de resources.

### 7.2 Modules Noyau

```
overlay       → Nécessaire pour le filesystem overlay de containerd
br_netfilter  → Permet à iptables de voir le trafic des bridges réseau
```

### 7.3 Paramètres Sysctl

```
net.bridge.bridge-nf-call-iptables  = 1  → Le trafic bridgé passe par iptables
net.bridge.bridge-nf-call-ip6tables = 1  → Idem pour IPv6
net.ipv4.ip_forward                 = 1  → Active le routage IP (requis pour les Pods)
```

### 7.4 Flannel — Comment ça marche

```
          Node A (10.244.0.0/24)          Node B (10.244.1.0/24)
         ┌──────────────────┐            ┌──────────────────┐
         │  Pod A           │            │  Pod B           │
         │  10.244.0.5      │            │  10.244.1.3      │
         └────────┬─────────┘            └────────┬─────────┘
                  │                               │
         ┌────────▼─────────┐            ┌────────▼─────────┐
         │  flannel.1       │            │  flannel.1       │
         │  (VXLAN tunnel)  │◄══════════►│  (VXLAN tunnel)  │
         └────────┬─────────┘            └────────┬─────────┘
                  │                               │
         ┌────────▼─────────┐            ┌────────▼─────────┐
         │  enp0s8          │            │  enp0s8          │
         │  192.168.56.11   │◄──────────►│  192.168.56.12   │
         └──────────────────┘            └──────────────────┘
```

- Chaque noeud reçoit un sous-réseau `/24` (ex: 10.244.0.0/24, 10.244.1.0/24)
- Flannel encapsule le trafic Pod-to-Pod dans des paquets VXLAN
- Le trafic VXLAN circule via `enp0s8` (réseau host-only entre VMs)
- `--iface=enp0s8` force Flannel à utiliser la bonne interface (pas le NAT)

### 7.5 SystemdCgroup — Pourquoi ?

```
containerd config:  SystemdCgroup = true
```

Kubernetes et containerd doivent utiliser le **même driver de cgroups**.
Kubernetes utilise systemd par défaut, donc containerd doit aussi utiliser systemd.
Si les deux ne sont pas alignés, les Pods crashent avec des erreurs de cgroup.

---

## 8. Commandes Essentielles à Connaître

### 8.1 Commandes Vagrant (depuis ton PC Windows)

```powershell
# Démarrer le cluster
vagrant up

# Arrêter le cluster (sans perdre les données)
vagrant halt

# Redémarrer le cluster
vagrant halt
vagrant up

# Se connecter au master en SSH
vagrant ssh k8s-master

# Se connecter à un worker
vagrant ssh k8s-worker1

# Vérifier l'état des VMs
vagrant status

# Re-exécuter le provisioning (Ansible)
vagrant provision services

# Supprimer tout et recommencer
vagrant destroy -f
vagrant up
```

### 8.2 Commandes kubectl (depuis k8s-master)

#### Noeuds

```bash
# Voir tous les noeuds
kubectl get nodes

# Voir les noeuds avec plus de détails
kubectl get nodes -o wide

# Détails complets d'un noeud
kubectl describe node k8s-master
kubectl describe node k8s-worker1
```

#### Pods

```bash
# Tous les pods dans tous les namespaces
kubectl get pods -A

# Pods dans le namespace par défaut
kubectl get pods

# Pods avec détails (IP, noeud, etc.)
kubectl get pods -o wide

# Pods d'un namespace spécifique
kubectl get pods -n kube-system

# Détails d'un pod
kubectl describe pod <nom-du-pod>

# Logs d'un pod
kubectl logs <nom-du-pod>
kubectl logs <nom-du-pod> -f        # Suivre en temps réel
kubectl logs <nom-du-pod> --previous  # Logs du conteneur précédent (si crash)
```

#### Déploiements

```bash
# Créer un déploiement
kubectl create deployment nginx --image=nginx:alpine --replicas=3

# Voir les déploiements
kubectl get deployments

# Mettre à l'échelle
kubectl scale deployment nginx --replicas=5

# Mettre à jour l'image
kubectl set image deployment/nginx nginx=nginx:latest

# Voir le rollout
kubectl rollout status deployment/nginx

# Annuler un rollout
kubectl rollout undo deployment/nginx

# Supprimer un déploiement
kubectl delete deployment nginx
```

#### Services

```bash
# Exposer un déploiement
kubectl expose deployment nginx --port=80 --type=ClusterIP

# Voir les services
kubectl get svc

# Voir les endpoints (IPs des pods derrière un service)
kubectl get endpoints

# Supprimer un service
kubectl delete svc nginx
```

#### Namespaces

```bash
# Lister les namespaces
kubectl get namespaces

# Créer un namespace
kubectl create namespace mon-app

# Travailler dans un namespace
kubectl get pods -n mon-app
```

#### Debug et Diagnostic

```bash
# Événements récents du cluster
kubectl get events --sort-by=.metadata.creationTimestamp

# Exécuter une commande dans un pod
kubectl exec -it <pod> -- /bin/sh

# Lancer un pod de test temporaire
kubectl run test --image=busybox:1.36 --restart=Never --rm -it -- sh

# Top (utilisation CPU/RAM) — nécessite metrics-server
kubectl top nodes
kubectl top pods

# Info du cluster
kubectl cluster-info

# Dump complet pour debug
kubectl cluster-info dump
```

#### YAML et Apply

```bash
# Appliquer un fichier YAML
kubectl apply -f mon-fichier.yml

# Voir le YAML d'une resource existante
kubectl get deployment nginx -o yaml

# Supprimer via fichier YAML
kubectl delete -f mon-fichier.yml

# Dry run (tester sans appliquer)
kubectl apply -f mon-fichier.yml --dry-run=client
```

### 8.3 Commandes Rapides Combinées (depuis Windows)

```powershell
# Vérifier les noeuds sans se connecter en SSH
vagrant ssh k8s-master -c "kubectl get nodes"

# Vérifier les pods sans se connecter en SSH
vagrant ssh k8s-master -c "kubectl get pods -A"

# Lancer une commande quelconque
vagrant ssh k8s-master -c "kubectl get svc"
```

---

## 9. Guide de Vérification du Cluster

### 9.1 Vérification Rapide (30 secondes)

```powershell
# Depuis Windows :
vagrant ssh k8s-master -c "kubectl get nodes"
vagrant ssh k8s-master -c "kubectl get pods -A"
```

**Résultat attendu :**

```
NAME          STATUS   ROLES           AGE   VERSION
k8s-master    Ready    control-plane   Xm    v1.29.2
k8s-worker1   Ready    <none>          Xm    v1.29.2
k8s-worker2   Ready    <none>          Xm    v1.29.2
```

- ✅ Les **3 noeuds** doivent être **Ready**
- ✅ Tous les pods doivent être **Running** (12 pods au total)
- ❌ Si un noeud est **NotReady** → attendre quelques minutes ou vérifier kubelet

### 9.2 Vérification Complète (5 minutes)

Se connecter au master :

```powershell
vagrant ssh k8s-master
```

Puis exécuter :

```bash
# 1. Vérifier les noeuds
kubectl get nodes -o wide

# 2. Vérifier tous les pods système
kubectl get pods -A
# Les 12 pods doivent être Running :
#   - 3x kube-flannel-ds (un par noeud)
#   - 2x coredns
#   - 1x etcd
#   - 1x kube-apiserver
#   - 1x kube-controller-manager
#   - 1x kube-scheduler
#   - 3x kube-proxy (un par noeud)

# 3. Tester un déploiement
kubectl create deployment test-nginx --image=nginx:alpine --replicas=2
kubectl rollout status deployment/test-nginx --timeout=120s
kubectl get pods -l app=test-nginx -o wide
# → Vérifier que les pods sont sur DIFFÉRENTS workers

# 4. Tester le service et le DNS
kubectl expose deployment test-nginx --port=80 --type=ClusterIP
sleep 5
kubectl run curl-test --image=curlimages/curl:8.5.0 --restart=Never -- sleep 300
sleep 15
kubectl exec curl-test -- curl -s -m 10 -o /dev/null -w '%{http_code}' http://test-nginx.default.svc.cluster.local
# → Doit afficher : 200

# 5. Tester la résolution DNS
kubectl exec curl-test -- nslookup kubernetes.default.svc.cluster.local
# → Doit résoudre vers 10.96.0.1

# 6. Nettoyage
kubectl delete pod curl-test
kubectl delete deployment test-nginx
kubectl delete svc test-nginx
```

### 9.3 Checklist de Santé

| # | Vérification | Commande | Résultat Attendu |
|---|-------------|----------|-------------------|
| 1 | Noeuds Ready | `kubectl get nodes` | 3 noeuds Ready |
| 2 | Pods système | `kubectl get pods -A` | 12 pods Running |
| 3 | Déploiement | `kubectl create deployment test --image=nginx:alpine` | Pod Running |
| 4 | DNS interne | `nslookup kubernetes.default.svc.cluster.local` | Résolution OK |
| 5 | Service réseau | `curl http://service-name` | HTTP 200 |
| 6 | Pods multi-noeuds | `kubectl get pods -o wide` | Pods sur worker1 ET worker2 |

---

## 10. Dépannage (Troubleshooting)

### Problème : Un noeud est "NotReady"

```bash
# 1. Vérifier kubelet
sudo systemctl status kubelet

# 2. Voir les logs kubelet
sudo journalctl -u kubelet -f --no-pager | tail -50

# 3. Vérifier les conditions du noeud
kubectl describe node <nom-du-noeud> | grep -A5 Conditions
```

### Problème : Un pod est "Pending"

```bash
# Voir pourquoi
kubectl describe pod <nom-du-pod>
# → Regarder la section Events en bas
# Causes fréquentes : pas assez de CPU/RAM, pas de noeud disponible
```

### Problème : Un pod est "CrashLoopBackOff"

```bash
# Voir les logs
kubectl logs <nom-du-pod>
kubectl logs <nom-du-pod> --previous

# Détails
kubectl describe pod <nom-du-pod>
```

### Problème : DNS ne fonctionne pas

```bash
# Vérifier CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# Tester depuis un pod
kubectl run dns-test --image=busybox:1.36 --restart=Never --rm -it -- nslookup kubernetes
```

### Problème : Les pods ne communiquent pas entre noeuds

```bash
# Vérifier Flannel
kubectl get pods -n kube-flannel
kubectl logs -n kube-flannel -l app=flannel

# Vérifier que Flannel utilise la bonne interface
kubectl logs -n kube-flannel -l app=flannel | grep "Using interface"
# → Doit montrer enp0s8, PAS enp0s3
```

### Problème : Vagrant timeout au boot

```powershell
# Si "vagrant up" timeout, les VMs sont probablement OK
# Vérifier :
vagrant status

# Si nécessaire, recharger :
vagrant reload k8s-master
vagrant reload k8s-worker1
```

### Problème : Redémarrer le cluster après halt

```powershell
# 1. Démarrer les VMs
vagrant up

# 2. Attendre ~1-2 minutes que kubelet redémarre

# 3. Vérifier
vagrant ssh k8s-master -c "kubectl get nodes"
# Si "NotReady" → attendre encore 1-2 minutes, puis revérifier
```

---

## Aide-Mémoire Rapide

```
┌─────────────────────────────────────────────────────────────┐
│                    COMMANDES ESSENTIELLES                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  VAGRANT (Windows PowerShell) :                              │
│    vagrant up              → Démarrer le cluster             │
│    vagrant halt            → Arrêter le cluster              │
│    vagrant ssh k8s-master  → Se connecter au master          │
│    vagrant status          → État des VMs                    │
│    vagrant destroy -f      → Tout supprimer                  │
│                                                              │
│  KUBECTL (depuis k8s-master) :                               │
│    kubectl get nodes       → État des noeuds                 │
│    kubectl get pods -A     → Tous les pods                   │
│    kubectl get svc         → Les services                    │
│    kubectl describe <res>  → Détails d'une resource          │
│    kubectl logs <pod>      → Logs d'un pod                   │
│    kubectl apply -f <file> → Appliquer un YAML               │
│    kubectl delete <res>    → Supprimer une resource          │
│                                                              │
│  VÉRIFICATION RAPIDE :                                       │
│    vagrant ssh k8s-master -c "kubectl get nodes"             │
│    vagrant ssh k8s-master -c "kubectl get pods -A"           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```
vagrant ssh services -c "cd /home/vagrant/ansible && ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook -i inventory.ini playbook.yml --become -v" 2>&1