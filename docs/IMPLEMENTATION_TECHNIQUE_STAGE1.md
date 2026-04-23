# Implementation Technique du Projet Kubernetes (Vagrant + Ansible)

## 1. Objectif de ce document

Ce document explique uniquement la partie implementation:
- comment le projet est structure
- comment le provisioning s execute
- comment les roles Ansible sont implementes
- comment les VMs et les Pods communiquent
- comment verifier rapidement et en profondeur si le cluster est OK

Ce document ne couvre pas la theorie generale Kubernetes.

---

## 2. Stack et structure reelle du projet

- Hyperviseur: VirtualBox
- Provisioning VM: Vagrant
- Configuration OS + Kubernetes: Ansible (execute dans la VM services)
- Runtime conteneur: containerd
- Bootstrap cluster: kubeadm
- CNI: Flannel

Arborescence principale:
- Vagrantfile
- ansible/inventory.ini
- ansible/group_vars/all.yml
- ansible/playbook.yml
- ansible/roles/common/tasks/main.yml
- ansible/roles/containerd/tasks/main.yml
- ansible/roles/kubernetes/tasks/main.yml
- ansible/roles/master/tasks/main.yml
- ansible/roles/cni/tasks/main.yml
- ansible/roles/workers/tasks/main.yml

---

## 3. Comment le projet est execute (pipeline de provisioning)

Execution standard:
1. vagrant up
2. Vagrant cree et demarre 4 VMs
3. Le provisioner file copie ansible/ dans la VM services
4. Le provisioner file copie la cle SSH vagrant dans services
5. Le provisioner shell dans services:
   - prepare la cle
   - installe Ansible si absent
   - lance ansible-playbook
6. Le playbook configure les noeuds, initialise le master, installe Flannel, joint les workers, puis valide le cluster

Important:
- L orchestration Ansible n est pas faite depuis Windows mais depuis services
- Cela evite la dependance Ansible native sur l hote Windows

---

## 4. Implementation du Vagrantfile

## 4.1 Definition des VMs

Le tableau NODES centralise:
- nom
- IP privee host-only
- CPU
- RAM

VMs definies:
- k8s-master: 192.168.56.10
- k8s-worker1: 192.168.56.11
- k8s-worker2: 192.168.56.12
- services: 192.168.56.20

## 4.2 Config globale

- box: ubuntu/jammy64
- boot_timeout: 600
- synced_folder desactive pour performance
- config.ssh.insert_key = false pour conserver la cle vagrant commune

## 4.3 Reseau

Chaque VM a:
- interface NAT (internet)
- interface private_network avec IP statique 192.168.56.x (communication inter-VM)

## 4.4 Provider VirtualBox

Par VM:
- nom VM force
- CPU/RAM selon NODES
- GUI desactivee
- options perf: natdnshostresolver1, ioapic

## 4.5 Provisioning uniquement sur services

Condition cle:
- le shell provisioner est execute seulement sur la derniere VM du tableau (services)

Etapes:
1. upload ansible/
2. upload cle privee vagrant
3. shell script:
   - chmod/chown de la cle
   - installation Ansible conditionnelle
   - lancement playbook avec become

Point robuste ajoute:
- si ansible-playbook existe deja, on ne reinstalle pas
- sinon installation pip avec --break-system-packages pour compatibilite Ubuntu recente

---

## 5. inventory.ini: mapping SSH reel

Groupes:
- masters
- workers
- services
- k8s_cluster (children: masters + workers)

Connexion:
- utilisateur vagrant
- cle: /home/vagrant/.ssh/vagrant_rsa
- host checking desactive
- python interpreter force: /usr/bin/python3

Impact implementation:
- ansible depuis services atteint master/workers via 192.168.56.x

---

## 6. group_vars/all.yml: variables structurantes

Variables techniques critiques:
- kube_version: 1.29.2-1.1
- kube_major_version: 1.29
- pod_network_cidr: 10.244.0.0/16
- master_ip: 192.168.56.10
- kube_apt_key_url / kube_apt_repo (pkgs.k8s.io)
- flannel_manifest_url
- cluster_hosts (injecte dans /etc/hosts)

Impact implementation:
- versioning Kubernetes controle
- CIDR coherent avec Flannel
- kubeadm init cible la bonne IP master

---

## 7. playbook.yml: ordre d execution exact

Play 1 (hosts: k8s_cluster, become: true, gather_facts: true)
- roles: common, containerd, kubernetes

Play 2 (hosts: masters, become: true, gather_facts: false)
- roles: master, cni

Play 3 (hosts: workers, become: true, gather_facts: false)
- role: workers

Play 4 (hosts: masters, become: false, gather_facts: false)
- validation kubectl (nodes + pods)

Play 5 (hosts: services, become: true, gather_facts: true)
- role: common

Logique implementation:
- prerequis OS avant kubeadm
- init control plane avant join workers
- CNI avant validation finale

---

## 8. Explication pratique des mots cles Ansible utilises

## 8.1 become

Usage:
- become: true sur plays qui touchent systeme (apt, systemd, /etc)
- become: false sur commandes kubectl executees en user vagrant

Pourquoi:
- separe privilege root et operations utilisateur
- evite erreurs de permission sur ~/.kube/config

## 8.2 gather_facts

Usage:
- true quand on veut facts systeme ou contexte complet
- false quand on veut accelerer un play ciblant des actions directes

Pourquoi:
- optimisation temps de run
- reduction du bruit dans les runs repetes

## 8.3 register

Usage concret:
- swap_status (resultat swapon --show)
- kubeadm_init_check (presence admin.conf)
- join_command_result (kubeadm token create)
- flannel_check (presence daemonset)
- not_ready_count (validation nodes)

Pourquoi:
- capturer sortie/etat d une tache
- piloter la suite avec when/until

## 8.4 when

Exemples:
- desactiver swap seulement si actif
- lancer kubeadm init seulement si cluster non initialise
- appliquer Flannel seulement s il est absent
- join worker seulement s il n est pas deja membre

Pourquoi:
- idempotence reelle

## 8.5 changed_when

Usage:
- false pour commandes de lecture/verification

Pourquoi:
- garder un recap propre (changed seulement si vrai changement)

## 8.6 failed_when

Usage:
- flannel_check permet rc != 0 sans faire echouer le play

Pourquoi:
- transformer un test d existence en logique conditionnelle

## 8.7 until / retries / delay

Usage:
- wait nodes ready avec boucle de retry

Pourquoi:
- absorber la latence de convergence du cluster apres join

---

## 9. Implementation des roles (detail technique)

## 9.1 role common

Objectif:
- base OS compatible Kubernetes

Implementation:
1. check swap (register)
2. swapoff conditionnel
3. suppression swap dans fstab
4. modprobe overlay + br_netfilter
5. persistence modules dans /etc/modules-load.d/k8s.conf
6. sysctl Kubernetes dans /etc/sysctl.d/k8s.conf
7. application sysctl
8. apt update + paquets communs
9. injection cluster_hosts dans /etc/hosts

## 9.2 role containerd

Objectif:
- runtime conteneur pret pour kubelet

Implementation:
1. install package containerd
2. creation /etc/containerd
3. generation config par defaut (creates pour idempotence)
4. replace SystemdCgroup false -> true
5. enable/start service containerd

## 9.3 role kubernetes

Objectif:
- installer kubeadm/kubelet/kubectl avec version pinnee

Implementation:
1. creation /etc/apt/keyrings
2. import key GPG Kubernetes
3. ajout repo pkgs.k8s.io
4. install kubelet/kubeadm/kubectl version exacte
5. hold des paquets (dpkg selections)
6. enable kubelet

## 9.4 role master

Objectif:
- initialiser control plane et exporter join command

Implementation:
1. stat /etc/kubernetes/admin.conf
2. kubeadm init si absent (master_ip + pod_network_cidr)
3. creation /home/vagrant/.kube
4. copie admin.conf vers ~/.kube/config
5. generation join command
6. set_fact kube_join_command

## 9.5 role cni

Objectif:
- deployer Flannel avec la bonne interface reseau

Implementation:
1. check daemonset kube-flannel-ds
2. download manifest Flannel vers /tmp/kube-flannel.yml
3. patch manifest: ajout --iface=enp0s8
4. apply manifest patch
5. rollout status daemonset kube-flannel-ds

Point critique:
- enp0s8 force la communication overlay sur le reseau host-only 192.168.56.x

## 9.6 role workers

Objectif:
- joindre les workers dynamiquement

Implementation:
1. check /etc/kubernetes/kubelet.conf
2. execute hostvars['k8s-master']['kube_join_command'] si absent
3. debug de confirmation

---

## 10. Communication VM et Pod (implementation reseau)

## 10.1 Niveau VM

- Vagrant private network: 192.168.56.0/24
- Les VMs se resolvent via /etc/hosts injecte par role common
- SSH Ansible utilise 192.168.56.x

## 10.2 Niveau Kubernetes

- kubeadm configure cluster et kubelet
- Flannel cree l overlay Pod network 10.244.0.0/16
- kube-proxy programme les regles de service
- CoreDNS fournit la resolution DNS interne

Chemin type pod->pod inter-noeud:
1. Pod source envoie vers IP pod distante
2. paquet encapsule via flannel vxlan
3. transit via interface enp0s8 entre VMs
4. decapsulation sur noeud destination
5. livraison au pod cible

---

## 11. Commandes techniques a connaitre (operationnel)

## 11.1 Cycle infrastructure

- vagrant status
- vagrant up
- vagrant halt
- vagrant reload k8s-master
- vagrant provision services
- vagrant destroy -f

## 11.2 Verification cluster rapide

- vagrant ssh k8s-master -c "kubectl get nodes"
- vagrant ssh k8s-master -c "kubectl get pods -A"
- vagrant ssh k8s-master -c "kubectl get pods -n kube-flannel -o wide"

## 11.3 Verification technique detaillee

- vagrant ssh k8s-master -c "kubectl get nodes -o wide"
- vagrant ssh k8s-master -c "kubectl describe node k8s-master"
- vagrant ssh k8s-master -c "kubectl get ds -n kube-flannel"
- vagrant ssh k8s-master -c "kubectl logs -n kube-flannel daemonset/kube-flannel-ds | grep -E 'Using interface|iface'"
- vagrant ssh k8s-master -c "kubectl get pods -A -o wide"
- vagrant ssh k8s-master -c "kubectl get svc -A"
- vagrant ssh k8s-master -c "kubectl get endpoints -A"

## 11.4 Test fonctionnel reseau service

- vagrant ssh k8s-master -c "kubectl create deployment nginx-test --image=nginx:alpine --replicas=2"
- vagrant ssh k8s-master -c "kubectl rollout status deployment/nginx-test --timeout=120s"
- vagrant ssh k8s-master -c "kubectl expose deployment nginx-test --port=80 --type=ClusterIP"
- vagrant ssh k8s-master -c "kubectl run curl-test --image=curlimages/curl:8.5.0 --restart=Never --rm -i -- curl -s -m 10 -o /dev/null -w 'HTTP:%{http_code}' http://nginx-test.default.svc.cluster.local"
- vagrant ssh k8s-master -c "kubectl delete deployment nginx-test && kubectl delete svc nginx-test"

---

## 12. Lecture du PLAY RECAP (interpretation)

Exemple recap:
- ok=39 changed=1 unreachable=0 failed=0 skipped=5

Interpretation:
- ok: taches executees avec succes
- changed: changements reels appliques
- unreachable: probleme SSH/connectivite
- failed: echec bloquant
- skipped: taches ignorees par condition when

Regle pratique:
- si failed=0 partout, provisioning considere OK
- changed faible sur re-run = bon signe d idempotence

---

## 13. Procedure de verification finale standard

1. vagrant status
2. vagrant ssh k8s-master -c "kubectl get nodes"
3. vagrant ssh k8s-master -c "kubectl get pods -A"
4. verifier:
   - 3 nodes Ready
   - flannel daemonset present et pods Running sur 3 nodes
   - composants control-plane Running
5. optionnel: test deployment/service puis cleanup

Si ces checks passent, l implementation est valide et operationnelle.
