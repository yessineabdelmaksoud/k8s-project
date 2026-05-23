# ═══════════════════════════════════════════════
# Stage 3 — Execution Guide (Restructured)
# ═══════════════════════════════════════════════
# Architecture:
#   - services VM: Docker + Gitea + Nexus (containers)
#   - k8s cluster: MySQL (StatefulSet), Backend, Frontend, Jenkins (pods)
#   - Namespaces: database, backend, frontend, jenkins
# ═══════════════════════════════════════════════

# ═══════════════════════════════════════════════
# STEP 1 — Start VMs
# ═══════════════════════════════════════════════
# If `vagrant up` fails with `VERR_ALREADY_EXISTS` for `k8s-master`, clean the stale
# VirtualBox registration/folder first, then retry:
#   "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" unregistervm k8s-master --delete
#   Remove-Item -Recurse -Force "$env:USERPROFILE\VirtualBox VMs\k8s-master"
# Then run `vagrant up --no-provision` again.
vagrant up --no-provision

# ═══════════════════════════════════════════════
# STEP 2 — Verify K8s cluster is ready
# ═══════════════════════════════════════════════
vagrant ssh k8s-master -c "kubectl get nodes"
vagrant ssh k8s-master -c "kubectl get pods -A"

# ═══════════════════════════════════════════════
# STEP 3 — Upload ALL Ansible files to services VM
# ═══════════════════════════════════════════════

# Create role directories
vagrant ssh services -c "mkdir -p /home/vagrant/ansible/roles/docker/{tasks,handlers}"
vagrant ssh services -c "mkdir -p /home/vagrant/ansible/roles/gitea/tasks"
vagrant ssh services -c "mkdir -p /home/vagrant/ansible/roles/nexus/tasks"
vagrant ssh services -c "mkdir -p /home/vagrant/ansible/roles/mysql/{tasks,files}"
vagrant ssh services -c "mkdir -p /home/vagrant/ansible/roles/backend/{tasks,files}"
vagrant ssh services -c "mkdir -p /home/vagrant/ansible/roles/frontend/{tasks,files}"
vagrant ssh services -c "mkdir -p /home/vagrant/ansible/roles/jenkins/{tasks,files}"
vagrant ssh services -c "mkdir -p /home/vagrant/ansible/roles/ingress/{tasks,files}"
vagrant ssh services -c "mkdir -p /home/vagrant/ansible/roles/vault/{tasks,files}"

# Upload playbook + group_vars
vagrant upload ansible/playbook.yml /home/vagrant/ansible/playbook.yml services
vagrant upload ansible/group_vars/all.yml /home/vagrant/ansible/group_vars/all.yml services

# Upload docker role
vagrant upload ansible/roles/docker/tasks/main.yml /home/vagrant/ansible/roles/docker/tasks/main.yml services
vagrant upload ansible/roles/docker/handlers/main.yml /home/vagrant/ansible/roles/docker/handlers/main.yml services

# Upload gitea role
vagrant upload ansible/roles/gitea/tasks/main.yml /home/vagrant/ansible/roles/gitea/tasks/main.yml services

# Upload nexus role
vagrant upload ansible/roles/nexus/tasks/main.yml /home/vagrant/ansible/roles/nexus/tasks/main.yml services

# Upload nfs_server role (updated with jenkins export)
vagrant upload ansible/roles/nfs_server/tasks/main.yml /home/vagrant/ansible/roles/nfs_server/tasks/main.yml services

# Upload mysql role
vagrant upload ansible/roles/mysql/tasks/main.yml /home/vagrant/ansible/roles/mysql/tasks/main.yml services
vagrant upload ansible/roles/mysql/files/namespace.yaml /home/vagrant/ansible/roles/mysql/files/namespace.yaml services
vagrant upload ansible/roles/mysql/files/pv.yaml /home/vagrant/ansible/roles/mysql/files/pv.yaml services
vagrant upload ansible/roles/mysql/files/pvc.yaml /home/vagrant/ansible/roles/mysql/files/pvc.yaml services
vagrant upload ansible/roles/mysql/files/secret.yaml /home/vagrant/ansible/roles/mysql/files/secret.yaml services
vagrant upload ansible/roles/mysql/files/statefulset.yaml /home/vagrant/ansible/roles/mysql/files/statefulset.yaml services
vagrant upload ansible/roles/mysql/files/service.yaml /home/vagrant/ansible/roles/mysql/files/service.yaml services

# Upload backend role
vagrant upload ansible/roles/backend/tasks/main.yml /home/vagrant/ansible/roles/backend/tasks/main.yml services
vagrant upload ansible/roles/backend/files/namespace.yaml /home/vagrant/ansible/roles/backend/files/namespace.yaml services
vagrant upload ansible/roles/backend/files/secret.yaml /home/vagrant/ansible/roles/backend/files/secret.yaml services
vagrant upload ansible/roles/backend/files/deployment.yaml /home/vagrant/ansible/roles/backend/files/deployment.yaml services
vagrant upload ansible/roles/backend/files/service.yaml /home/vagrant/ansible/roles/backend/files/service.yaml services

# Upload frontend role
vagrant upload ansible/roles/frontend/tasks/main.yml /home/vagrant/ansible/roles/frontend/tasks/main.yml services
vagrant upload ansible/roles/frontend/files/namespace.yaml /home/vagrant/ansible/roles/frontend/files/namespace.yaml services
vagrant upload ansible/roles/frontend/files/deployment.yaml /home/vagrant/ansible/roles/frontend/files/deployment.yaml services
vagrant upload ansible/roles/frontend/files/service.yaml /home/vagrant/ansible/roles/frontend/files/service.yaml services

# Upload jenkins role
vagrant upload ansible/roles/jenkins/tasks/main.yml /home/vagrant/ansible/roles/jenkins/tasks/main.yml services
vagrant upload ansible/roles/jenkins/files/namespace.yaml /home/vagrant/ansible/roles/jenkins/files/namespace.yaml services
vagrant upload ansible/roles/jenkins/files/serviceaccount.yaml /home/vagrant/ansible/roles/jenkins/files/serviceaccount.yaml services
vagrant upload ansible/roles/jenkins/files/pv.yaml /home/vagrant/ansible/roles/jenkins/files/pv.yaml services
vagrant upload ansible/roles/jenkins/files/pvc.yaml /home/vagrant/ansible/roles/jenkins/files/pvc.yaml services
vagrant upload ansible/roles/jenkins/files/deployment.yaml /home/vagrant/ansible/roles/jenkins/files/deployment.yaml services
vagrant upload ansible/roles/jenkins/files/service.yaml /home/vagrant/ansible/roles/jenkins/files/service.yaml services

# Upload ingress role
vagrant upload ansible/roles/ingress/tasks/main.yml /home/vagrant/ansible/roles/ingress/tasks/main.yml services
vagrant upload ansible/roles/ingress/files/backend-alias.yaml /home/vagrant/ansible/roles/ingress/files/backend-alias.yaml services
vagrant upload ansible/roles/ingress/files/app-ingress.yaml /home/vagrant/ansible/roles/ingress/files/app-ingress.yaml services

# Upload vault role
vagrant upload ansible/roles/vault/tasks/main.yml /home/vagrant/ansible/roles/vault/tasks/main.yml services
vagrant upload ansible/roles/vault/files/vault.hcl /home/vagrant/ansible/roles/vault/files/vault.hcl services

# ═══════════════════════════════════════════════
# STEP 4 — Run Ansible: Services VM (Docker + Gitea + Nexus) — ~10 min
# ═══════════════════════════════════════════════
vagrant ssh services -c "cd /home/vagrant/ansible && ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook -i inventory.ini playbook.yml --tags services --become -v"

# ═══════════════════════════════════════════════
# STEP 5 — Verify services VM containers
# ═══════════════════════════════════════════════
vagrant ssh services -c "sudo docker ps"
vagrant ssh services -c "curl -s -o /dev/null -w '%{http_code}' http://localhost:3000"
vagrant ssh services -c "curl -s -o /dev/null -w '%{http_code}' http://localhost:8081"

# ═══════════════════════════════════════════════
# STEP 6 — Nexus setup (password + Docker repo on port 8082)
# ═══════════════════════════════════════════════
vagrant upload scripts/nexus-setup.sh /home/vagrant/nexus-setup.sh services
vagrant ssh services -c "chmod +x /home/vagrant/nexus-setup.sh && bash /home/vagrant/nexus-setup.sh"

# Verify Docker registry
vagrant ssh services -c "curl -s -u admin:admin123 http://localhost:8081/v2/_catalog"

# ═══════════════════════════════════════════════
# STEP 6B — Vault (optional, dev mode)
# ═══════════════════════════════════════════════
vagrant ssh services -c "cd /home/vagrant/ansible && ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook -i inventory.ini playbook.yml --tags vault -v"

# ═══════════════════════════════════════════════
# STEP 7 — Run Ansible: Docker on workers — ~5 min
# ═══════════════════════════════════════════════
vagrant ssh services -c "cd /home/vagrant/ansible && ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook -i inventory.ini playbook.yml --tags docker-workers --become -v"

# ═══════════════════════════════════════════════
# STEP 8 — Run Ansible: K8s Apps (MySQL + Backend + Frontend + Jenkins) — ~5 min
# ═══════════════════════════════════════════════
vagrant ssh services -c "cd /home/vagrant/ansible && ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook -i inventory.ini playbook.yml --tags apps --become -v"

# ═══════════════════════════════════════════════
# STEP 9 — Verify all namespaces and pods
# ═══════════════════════════════════════════════

# Namespaces
vagrant ssh k8s-master -c "kubectl get ns"

# MySQL StatefulSet
vagrant ssh k8s-master -c "kubectl get statefulset -n database"
vagrant ssh k8s-master -c "kubectl get pods -n database"

# Backend
vagrant ssh k8s-master -c "kubectl get pods -n backend"
vagrant ssh k8s-master -c "kubectl get svc -n backend"

# Frontend
vagrant ssh k8s-master -c "kubectl get pods -n frontend"
vagrant ssh k8s-master -c "kubectl get svc -n frontend"

# Jenkins
vagrant ssh k8s-master -c "kubectl get pods -n jenkins"
vagrant ssh k8s-master -c "kubectl get svc -n jenkins"

# All pods across all namespaces
vagrant ssh k8s-master -c "kubectl get pods -A -o wide"

# ═══════════════════════════════════════════════
# STEP 10 — Jenkins initial password
# ═══════════════════════════════════════════════
vagrant ssh k8s-master -c "kubectl exec -n jenkins deployment/jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword"

# Verify kubectl from Jenkins pod
vagrant ssh k8s-master -c "kubectl exec -n jenkins deployment/jenkins -- kubectl get nodes"

# Verify docker from Jenkins pod
vagrant ssh k8s-master -c "kubectl exec -n jenkins deployment/jenkins -- docker info --format '{{.ServerVersion}}'"

# ═══════════════════════════════════════════════
# STEP 11 — Push App Code to Gitea (Required for Jenkins)
# ═══════════════════════════════════════════════
# Before Jenkins can run the pipelines, the code must be in Gitea!
# 
# 1. Open Gitea: http://192.168.56.20:3000
# 2. Register first user (Admin): Username: vagrant / Password: vagrant123
# 3. Create two new empty repositories: "backend" and "frontend"
# 4. Upload your local code to the services VM:
vagrant upload app /home/vagrant/app services




# 5. Push the backend code to Gitea:
vagrant ssh services -c "cd /home/vagrant/app/backend && git init && git checkout -b main && git config user.email 'vagrant@local' && git config user.name 'vagrant' && git add . && git commit -m 'init' && git remote add origin http://vagrant:vagrant123@localhost:3000/vagrant/backend.git && git push -u origin main"

# 6. Push the frontend code to Gitea:
vagrant ssh services -c "cd /home/vagrant/app/frontend && git init && git checkout -b main && git config user.email 'vagrant@local' && git config user.name 'vagrant' && git add . && git commit -m 'init' && git remote add origin http://vagrant:vagrant123@localhost:3000/vagrant/frontend.git && git push -u origin main"

vagrant ssh services -c "cd /home/vagrant/app/frontend && git push -u origin main --force"
vagrant ssh services -c "cd /home/vagrant/app/backend && git push -u origin main --force"

# ═══════════════════════════════════════════════
# STEP 12 — Ingress (optional: single entrypoint)
# ═══════════════════════════════════════════════

# Option A: Run the Ansible ingress role (recommended)
vagrant ssh services -c "cd /home/vagrant/ansible && ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook -i inventory.ini playbook.yml --tags ingress -v"

# Option B: Manual kubectl steps

# Install ingress-nginx for bare metal
vagrant ssh k8s-master -c "kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/baremetal/deploy.yaml"

# Force a fixed NodePort for HTTP
vagrant ssh k8s-master -c "kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' -p='[{\"op\":\"replace\",\"path\":\"/spec/ports/0/nodePort\",\"value\":30090}]'"

# Create an ExternalName service in frontend namespace that points to backend
vagrant ssh k8s-master -c "cat > /tmp/backend-alias.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
	name: backend
	namespace: frontend
spec:
	type: ExternalName
	externalName: backend.backend.svc.cluster.local
	ports:
	- port: 8080
		targetPort: 8080
EOF
kubectl apply -f /tmp/backend-alias.yaml"

# Create ingress that routes /api to backend and / to frontend
vagrant ssh k8s-master -c "cat > /tmp/app-ingress.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
	name: app-ingress
	namespace: frontend
spec:
	ingressClassName: nginx
	rules:
	- host: k8s-app.local
		http:
			paths:
			- path: /api
				pathType: Prefix
				backend:
					service:
						name: backend
						port:
							number: 8080
			- path: /
				pathType: Prefix
				backend:
					service:
						name: frontend
						port:
							number: 80
EOF
kubectl apply -f /tmp/app-ingress.yaml"

# Test ingress routing from any VM
vagrant ssh services -c "curl -H 'Host: k8s-app.local' http://192.168.56.11:30090/api/health"

# ═══════════════════════════════════════════════
# STEP 13 — URLs d'accès
# ═══════════════════════════════════════════════
# Gitea    : http://192.168.56.20:3000
# Nexus    : http://192.168.56.20:8081   (admin / admin123)
# Registry : 192.168.56.20:8082
# Jenkins  : http://192.168.56.11:32000  (or http://192.168.56.12:32000)
# Backend  : http://192.168.56.11:30080/api/health  (after pipeline)
# Frontend : http://192.168.56.11:30000              (after pipeline)

# ═══════════════════════════════════════════════
# Running specific tags only (examples)
# ═══════════════════════════════════════════════
# Only MySQL:
#   ansible-playbook playbook.yml --tags mysql
# Only Jenkins:
#   ansible-playbook playbook.yml --tags jenkins
# Only services VM:
#   ansible-playbook playbook.yml --tags services
# Everything:
#   ansible-playbook playbook.yml



vagrant ssh k8s-master -c "kubectl get deployment jenkins -n jenkins -o yaml"


vagrant ssh k8s-master -c "kubectl exec -n jenkins deployment/jenkins -- docker info"



Étape 1 : Ajouter les identifiants Nexus
Le pipeline a besoin de s'authentifier auprès de votre registre Docker Nexus, et il cherchera un identifiant nommé exactement nexus-credentials.

Dans le menu de gauche, cliquez sur Gérer Jenkins (Manage Jenkins).
Sous Sécurité, cliquez sur Credentials (Identifiants).
Cliquez sur la flèche à côté de (global) puis sur Add Credentials (Ajouter des identifiants).
Remplissez le formulaire exactement comme suit :
Kind : Username with password
Scope : Global
Username : admin
Password : admin123
ID : nexus-credentials (⚠️ très important, ne vous trompez pas sur l'ID)
Description : Nexus Docker Registry
Cliquez sur Create (Créer).



Étape 2 : Créer le Job pour le Backend
Retournez sur le tableau de bord Jenkins et cliquez sur Nouveau Item ou Créer un job.
Entrez le nom : backend-pipeline
Sélectionnez Pipeline et cliquez sur OK.
Descendez tout en bas vers la section Pipeline :
Definition : Choisissez Pipeline script from SCM
SCM : Git
Repository URL : http://192.168.56.20:3000/vagrant/backend.git
Branch Specifier : */main
Script Path : Jenkinsfile
Cliquez sur Sauvegarder (Save).
Lancez-le en cliquant sur Lancer la construction (Build Now) dans le menu de gauche.
Attendez que le pipeline passe au vert. Cela va construire l'image Node.js, la pousser sur Nexus, et déployer le backend sur le cluster Kubernetes.


vagrant ssh services -c "cd /home/vagrant/app/backend && sed -i '/NAMESPACE    = \"backend\"/a \        KUBECONFIG   = \"/var/jenkins_home/.kube/config\"' Jenkinsfile && git add Jenkinsfile && git commit -m 'fix kubeconfig' && git push origin main"


Pour vérifier que tout est vraiment bon, fais dans cet ordre:

Relancer uniquement Jenkins via Ansible: vagrant ssh services -c "cd /home/vagrant/ansible && ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook -i inventory.ini playbook.yml --tags jenkins --become -v"
Vérifier depuis le pod Jenkins que l’accès Kubernetes fonctionne: vagrant ssh k8s-master -c "kubectl exec -n jenkins deployment/jenkins -- kubectl get nodes"
Vérifier le Docker runtime dans Jenkins: vagrant ssh k8s-master -c "kubectl exec -n jenkins deployment/jenkins -- docker info --format '{{.ServerVersion}}'"
Lancer un build backend et un build frontend dans Jenkins, puis contrôler que les stages Build, Push, Deploy et Verify passent au vert.
Si un pipeline échoue encore, ouvre la console du job et envoie-moi la première erreur exacte; je te dirai quoi corriger sans tâtonner.