# Implementation Technique — Stage 3 : CI/CD Pipeline & Application Deployment

## 1. Objectif de ce document

Ce document explique l'implementation technique du Stage 3 :
- comment la stack CI/CD (Gitea, Nexus, Jenkins) est deployee sur la VM services
- comment Docker est installe et configure via Ansible
- comment Nexus est configure comme registre Docker prive
- comment les applications backend/frontend sont conteneurisees
- comment Helm orchestre le deploiement sur Kubernetes
- comment Jenkins automatise le pipeline CI/CD complet
- comment kubectl et helm sont injectes dans le conteneur Jenkins

Ce document ne couvre pas les stages precedents (provisioning VM, cluster K8s, stockage NFS, MySQL).

---

## 2. Architecture Stage 3

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           Windows Host (VirtualBox)                          │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                        services VM — 192.168.56.20                     │  │
│  │                                                                        │  │
│  │   ┌──────────┐    ┌──────────┐    ┌──────────────┐                    │  │
│  │   │  Gitea   │    │  Nexus   │    │   Jenkins    │                    │  │
│  │   │  :3000   │    │  :8081   │    │   :8080      │                    │  │
│  │   │  :2222   │    │  :8082   │    │   :50000     │                    │  │
│  │   │          │    │ (Docker  │    │  kubectl     │                    │  │
│  │   │  Git     │    │ Registry)│    │  helm        │                    │  │
│  │   └──────────┘    └──────────┘    └──────┬───────┘                    │  │
│  │                                          │ kubeconfig                  │  │
│  │   Docker Engine ── /var/run/docker.sock ─┘                            │  │
│  │   daemon.json: insecure-registries [192.168.56.20:8082]               │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                          │                                   │
│               ┌──────────────────────────┼──────────────────────┐            │
│               │                          │                      │            │
│  ┌────────────▼──────┐  ┌────────────────▼───┐  ┌──────────────▼────────┐  │
│  │   k8s-master      │  │   k8s-worker1      │  │   k8s-worker2         │  │
│  │   192.168.56.10   │  │   192.168.56.11    │  │   192.168.56.12       │  │
│  │                   │  │                     │  │                       │  │
│  │   Control Plane   │  │  backend pods (x2)  │  │  frontend pods (x2)  │  │
│  │   MySQL pod       │  │  NodePort 30080     │  │  NodePort 30000      │  │
│  └───────────────────┘  └─────────────────────┘  └───────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Arborescence des fichiers Stage 3

```
cluster/
├── ansible/
│   ├── playbook.yml                              ← mis a jour (ajout services_stack)
│   └── roles/
│       └── services_stack/
│           ├── tasks/main.yml                    ← Docker + conteneurs
│           └── handlers/main.yml                 ← handler restart docker
├── app/
│   ├── backend/
│   │   ├── Dockerfile                            ← image Node.js
│   │   └── Jenkinsfile                           ← pipeline CI/CD backend
│   └── frontend/
│       ├── Dockerfile                            ← image multi-stage React+nginx
│       ├── nginx.conf                            ← proxy /api/ vers backend
│       └── Jenkinsfile                           ← pipeline CI/CD frontend
├── helm/
│   ├── backend/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       └── service.yaml
│   └── frontend/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           └── service.yaml
├── scripts/
│   ├── nexus-setup.sh                            ← config repo Docker + password
│   ├── jenkins-kubectl-setup.sh                  ← inject kubectl/helm dans Jenkins
│   └── deploy-stage3.sh                          ← orchestration deploiement complet
└── run.md                                        ← commandes d'execution pas-a-pas
```

---

## 4. Role Ansible : services_stack

### 4.1 Objectif

Installer Docker sur la VM services et demarrer trois conteneurs DevOps :
- Gitea (depot Git auto-heberge)
- Nexus (registre Docker prive + gestionnaire d'artefacts)
- Jenkins (serveur CI/CD)

### 4.2 Implementation tasks/main.yml

Le role suit une sequence stricte de 12 taches :

**Tache 1 — Stop unattended-upgrades**
```yaml
- name: Stop unattended-upgrades service
  ansible.builtin.systemd:
    name: unattended-upgrades
    state: stopped
    enabled: false
  ignore_errors: true
```
Pourquoi :
- Ubuntu 22.04 lance des mises a jour automatiques qui verrouillent apt
- ignore_errors car le service peut ne pas exister sur certaines images
- Sans ca, l'installation Docker echoue aleatoirement avec "Could not get lock"

**Tache 2 — Install docker.io**
```yaml
- name: Install docker.io
  ansible.builtin.apt:
    name: docker.io
    state: present
    update_cache: true
```
Pourquoi :
- docker.io est le paquet Docker officiel des repos Ubuntu
- update_cache assure un index apt frais apres l'arret d'unattended-upgrades
- On n'utilise pas Docker CE (docker-ce) car docker.io suffit et evite l'ajout du repo Docker officiel

**Tache 3 — Enable et start Docker**
```yaml
- name: Enable and start Docker service
  ansible.builtin.systemd:
    name: docker
    state: started
    enabled: true
```
Pourquoi :
- enabled: true assure le demarrage automatique apres reboot de la VM
- state: started est idempotent (ne redemarre pas si deja started)

**Tache 4 — Ajout vagrant au groupe docker**
```yaml
- name: Add vagrant user to docker group
  ansible.builtin.user:
    name: vagrant
    groups: docker
    append: true
```
Pourquoi :
- Permet d'executer docker sans sudo
- append: true preserve les groupes existants (ne remplace pas)

**Tache 4b — Installation Python docker SDK**
```yaml
- name: Install Python docker SDK
  ansible.builtin.pip:
    name: docker
    state: present
    executable: pip3
```
Pourquoi :
- Le module Ansible `community.docker.docker_container` necessite le SDK Python docker
- Sans ce SDK, les taches de creation de conteneurs echouent avec "Failed to import docker"

**Tache 4c — Installation collection community.docker**
```yaml
- name: Install community.docker Ansible collection
  ansible.builtin.command: ansible-galaxy collection install community.docker
  become: false
  changed_when: false
```
Pourquoi :
- La collection fournit le module docker_container
- become: false car ansible-galaxy installe dans $HOME de l'utilisateur vagrant
- changed_when: false car la commande est idempotente (ne reinstalle pas si present)

**Tache 5 — Creation des repertoires de donnees**
```yaml
- name: Create service data directories
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    mode: "0755"
  loop:
    - /srv/gitea
    - /srv/nexus
    - /srv/jenkins
```
Pourquoi :
- Chaque conteneur persiste ses donnees dans un volume Docker monte sur /srv/
- Cela survit aux redemarrages et suppressions de conteneurs
- Mode 0755 donne lecture/traversee a tous mais ecriture seulement a root

**Tache 6 — Ownership Nexus**
```yaml
- name: Set /srv/nexus owner to uid=200 gid=200
  ansible.builtin.file:
    path: /srv/nexus
    owner: "200"
    group: "200"
    recurse: true
```
Pourquoi :
- Le conteneur Nexus s'execute avec UID/GID 200 en interne
- Sans ce changement de proprietaire, Nexus ne peut pas ecrire dans /nexus-data
- Le conteneur tombe en CrashLoop avec "Unable to create directory"

**Taches 7, 8, 9 — Demarrage des conteneurs**

Les trois conteneurs sont crees avec le module `community.docker.docker_container` :

| Conteneur | Image | Ports | Volume host |
|-----------|-------|-------|-------------|
| gitea | gitea/gitea:latest | 3000:3000, 2222:22 | /srv/gitea:/data |
| nexus | sonatype/nexus3:latest | 8081:8081 | /srv/nexus:/nexus-data |
| jenkins | jenkins/jenkins:lts | 8080:8080, 50000:50000 | /srv/jenkins:/var/jenkins_home, /var/run/docker.sock |

Points critiques :
- restart_policy: always — les conteneurs redemarrent automatiquement
- Jenkins monte le socket Docker (`/var/run/docker.sock`) pour pouvoir construire des images Docker depuis l'interieur du pipeline
- Le port 2222 de Gitea evite le conflit avec le SSH systeme (port 22)
- Le port 50000 de Jenkins est pour la communication agent JNLP

**Tache 10 — Configuration insecure registry**
```yaml
- name: Configure Docker insecure registry
  ansible.builtin.copy:
    dest: /etc/docker/daemon.json
    content: |
      {
        "insecure-registries": ["192.168.56.20:8082"]
      }
  notify: restart docker
```
Pourquoi :
- Le repo Docker Nexus ecoute sur le port 8082 sans TLS
- Docker refuse par defaut de communiquer avec un registre non-HTTPS
- insecure-registries autorise les push/pull en HTTP vers cette adresse
- notify declenche le handler pour que Docker relise sa configuration

**Tache 11 — Flush handlers**
```yaml
- name: Flush handlers
  ansible.builtin.meta: flush_handlers
```
Pourquoi :
- Force le restart Docker immediatement (au lieu d'attendre la fin du play)
- Necessaire car la tache suivante (wait Nexus) depend du Docker restart

**Tache 12 — Attente Nexus ready**
```yaml
- name: Wait for Nexus to be ready
  ansible.builtin.uri:
    url: http://localhost:8081
    status_code: 200
  register: nexus_result
  until: nexus_result.status == 200
  retries: 30
  delay: 15
```
Pourquoi :
- Nexus met environ 2-4 minutes a initialiser au premier demarrage
- 30 retries × 15s = 7m30 maximum d'attente
- Le module uri fait un GET HTTP et verifie le code retour
- Sans cette attente, les scripts Nexus post-install echouent

### 4.3 Implementation handlers/main.yml

```yaml
- name: restart docker
  ansible.builtin.systemd:
    name: docker
    state: restarted
```
Pourquoi :
- Declenche quand daemon.json change (notify dans tache 10)
- Restart au lieu de reload car Docker necessite un restart complet pour relire daemon.json
- Les conteneurs avec restart_policy: always redemarrent automatiquement apres le restart Docker

---

## 5. Mise a jour du playbook.yml

### 5.1 Changement

Play 5 avant (Stage 2) :
```yaml
- name: Prepare services node
  hosts: services
  become: true
  gather_facts: true
  roles:
    - role: common
    - role: nfs_server
```

Play 5 apres (Stage 3) :
```yaml
- name: Prepare services node
  hosts: services
  become: true
  gather_facts: true
  roles:
    - role: common
    - role: nfs_server
    - role: services_stack    # ← ajout Stage 3
```

### 5.2 Logique d'execution

L'ordre des roles dans Play 5 est important :
1. `common` — configure le systeme de base, /etc/hosts, desactive swap
2. `nfs_server` — installe et configure le serveur NFS (requis pour les PV Kubernetes)
3. `services_stack` — installe Docker et lance les conteneurs CI/CD

Le role services_stack doit s'executer apres common car il depende d'apt fonctionnel et d'une resolution DNS correcte.

---

## 6. Script nexus-setup.sh — Configuration post-demarrage Nexus

### 6.1 Objectif

Configurer Nexus pour servir de registre Docker prive apres son premier demarrage.

### 6.2 Etapes d'execution

**Etape 1 — Attente de l'API Nexus**
```bash
until curl -sf "${NEXUS_URL}/service/rest/v1/status" > /dev/null 2>&1; do
    sleep 10
done
```
Pourquoi :
- L'API REST Nexus n'est disponible qu'apres initialisation complete
- Le endpoint /service/rest/v1/status retourne 200 quand Nexus est pret
- -sf : silent + fail sans afficher le body en cas d'erreur

**Etape 2 — Recuperation du mot de passe initial**
```bash
INIT_PASSWORD=$(docker exec nexus cat /nexus-data/admin.password)
```
Pourquoi :
- Au premier demarrage, Nexus genere un mot de passe admin aleatoire
- Ce fichier est cree dans /nexus-data (monte depuis /srv/nexus sur l'hote)
- docker exec lit directement depuis le conteneur en cours d'execution

**Etape 3 — Changement du mot de passe admin**
```bash
curl -sf -X PUT "${NEXUS_URL}/service/rest/v1/security/users/admin/change-password" \
    -H "Content-Type: text/plain" \
    -u "admin:${INIT_PASSWORD}" \
    -d "${NEW_PASSWORD}"
```
Pourquoi :
- Le mot de passe est change vers `admin123` pour faciliter l'automatisation
- Content-Type text/plain car l'API attend le nouveau mot de passe en brut
- -u utilise l'authentification Basic avec le mot de passe initial

**Etape 4 — Creation du repo Docker hosted**
```bash
curl -sf -X POST "${NEXUS_URL}/service/rest/v1/repositories/docker/hosted" \
    -H "Content-Type: application/json" \
    -u "admin:${NEW_PASSWORD}" \
    -d '{
        "name": "docker-private",
        "online": true,
        "storage": {
            "blobStoreName": "default",
            "strictContentTypeValidation": true,
            "writePolicy": "ALLOW"
        },
        "docker": {
            "v1Enabled": false,
            "forceBasicAuth": true,
            "httpPort": 8082
        }
    }'
```
Pourquoi :
- "docker-private" est un repo de type Docker hosted (stocke les images localement)
- httpPort 8082 ouvre un port HTTP dedie pour le protocole Docker Registry API v2
- forceBasicAuth exige une authentification pour push/pull
- writePolicy ALLOW autorise les push (sinon le repo est read-only)
- blobStoreName "default" utilise le blob store par defaut ("file" sur disque)

**Etape 5 — Activation du Docker Bearer Token realm**
```bash
curl -sf -X PUT "${NEXUS_URL}/service/rest/v1/security/realms/active" \
    -H "Content-Type: application/json" \
    -u "admin:${NEW_PASSWORD}" \
    -d '[
        "NexusAuthenticatingRealm",
        "NexusAuthorizingRealm",
        "DockerToken"
    ]'
```
Pourquoi :
- Le protocole Docker Registry v2 utilise un mecanisme d'authentification par token
- Sans le realm DockerToken, `docker login` echoue
- On remet les deux realms par defaut (Authenticating + Authorizing) plus DockerToken

---

## 7. Dockerfiles applicatifs

### 7.1 Backend — Dockerfile

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
EXPOSE 8080
CMD ["node", "server.js"]
```

Implementation :
- node:20-alpine — image legere (~180MB vs ~1GB pour node:20)
- COPY package*.json avant COPY . . — exploite le cache Docker : les layers npm install ne sont reconstruites que si package.json change
- --production — n'installe pas les devDependencies (reduit taille image)
- EXPOSE 8080 — documentation du port, correspond a la variable d'env du backend
- server.js — point d'entree qui expose GET /api/health et se connecte a MySQL via les env vars (DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD)

### 7.2 Frontend — Dockerfile multi-stage

```dockerfile
# Stage 1: Build the React application
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# Stage 2: Serve with nginx
FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

Implementation :
- Multi-stage build :
  - Stage 1 (build) : installe les deps, compile React avec Vite (genere /app/dist)
  - Stage 2 (runtime) : image nginx:alpine (~40MB), copie uniquement le build final
- L'image finale ne contient ni Node.js, ni node_modules, ni le code source
- La taille finale est ~40-50MB au lieu de ~500MB+ pour un build single-stage
- nginx.conf remplace la config par defaut pour ajouter le proxy /api/

### 7.3 nginx.conf — Configuration proxy

```nginx
server {
    listen 80;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    # Serve static files
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Proxy API requests to the backend NodePort
    location /api/ {
        proxy_pass http://192.168.56.11:30080/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Implementation :
- server_name _ — accept toute requete quel que soit le Host header
- try_files $uri $uri/ /index.html — SPA routing : toutes les routes non-trouvees renvoient vers index.html (necessaire pour React Router)
- location /api/ — toutes les requetes /api/* sont forwardees au backend
- proxy_pass cible le NodePort 30080 sur k8s-worker1 (192.168.56.11)
- Les headers proxy preservent l'IP client originale et le protocole

---

## 8. Helm Charts

### 8.1 Pourquoi Helm

- Gestion du deploiement Kubernetes via templates parametrables
- Permet helm upgrade --install avec --set image.tag pour changer le tag a chaque build Jenkins
- Rollback facile avec helm rollback
- Separation configuration (values.yaml) et structure (templates/)

### 8.2 Chart backend

**Chart.yaml**
```yaml
apiVersion: v2
name: backend
description: A Helm chart for the backend Node.js application
type: application
version: 0.1.0
appVersion: "1.0"
```
- apiVersion v2 : format Helm 3
- version : versionning du chart lui-meme
- appVersion : version de l'application deployee

**values.yaml**
```yaml
image:
  repository: 192.168.56.20:8082/backend
  tag: latest
  pullPolicy: Always

replicaCount: 2

service:
  type: NodePort
  port: 8080
  nodePort: 30080

env:
  DB_HOST: mysql-svc
  DB_PORT: "3306"
  DB_NAME: appdb
  DB_USER: appuser

secretRef: mysql-secret
```

Variables cles :
- image.repository pointe vers le registre Nexus prive
- pullPolicy Always force le re-pull a chaque deploiement (important pour tag:latest)
- replicaCount 2 pour la haute disponibilite (pods repartis sur workers)
- nodePort 30080 expose le backend sur tous les noeuds
- env contient les variables de connexion MySQL (non sensibles)
- secretRef pointe vers mysql-secret qui contient DB_PASSWORD et les MYSQL_* vars

**templates/deployment.yaml**
```yaml
spec:
  replicas: {{ .Values.replicaCount }}
  ...
  containers:
    - name: {{ .Chart.Name }}
      image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      env:
        {{- range $key, $value := .Values.env }}
        - name: {{ $key }}
          value: "{{ $value }}"
        {{- end }}
      envFrom:
        - secretRef:
            name: {{ .Values.secretRef }}
      readinessProbe:
        httpGet:
          path: /api/health
          port: {{ .Values.service.port }}
        initialDelaySeconds: 10
        periodSeconds: 5
```

Points d'implementation :
- range $key, $value itere sur la map env dans values.yaml → genere des variables d'env individuelles
- envFrom secretRef injecte TOUTES les cles de mysql-secret comme variables d'env (inclut DB_PASSWORD, MYSQL_ROOT_PASSWORD, etc.)
- readinessProbe GET /api/health : Kubernetes n'envoie du trafic au pod que quand le health check passe
- initialDelaySeconds 10 : donne le temps a Node.js de demarrer et se connecter a MySQL

**templates/service.yaml**
```yaml
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.port }}
      nodePort: {{ .Values.service.nodePort }}
  selector:
    app: {{ .Release.Name }}
```
- NodePort 30080 rend le backend accessible depuis l'exterieur du cluster
- Le selector app: backend lie le service aux pods du deployment

### 8.3 Chart frontend

**values.yaml**
```yaml
image:
  repository: 192.168.56.20:8082/frontend
  tag: latest
  pullPolicy: Always

replicaCount: 2

service:
  type: NodePort
  port: 80
  nodePort: 30000
```

**templates/deployment.yaml**

Similaire au backend avec deux differences :
- Pas de bloc `env` ni `envFrom` (le frontend n'a pas besoin de variables d'env)
- readinessProbe sur path `/` (page HTML servie par nginx) au lieu de `/api/health`

**templates/service.yaml**
- NodePort 30000 expose le frontend sur tous les noeuds

---

## 9. Jenkinsfiles — Pipeline CI/CD

### 9.1 Structure commune

Les deux Jenkinsfiles (backend et frontend) suivent la meme structure :

```
environment → Checkout → Build Image → Push to Nexus → Copy Helm Chart → Deploy → Verify
```

### 9.2 Variables d'environnement

```groovy
environment {
    NEXUS_URL    = "192.168.56.20:8082"
    GITEA_URL    = "http://192.168.56.20:3000"
    IMAGE_NAME   = "backend"          // ou "frontend"
    KUBECONFIG   = "/var/jenkins_home/.kube/config"
    HELM_RELEASE = "backend"          // ou "frontend"
    HELM_CHART   = "/var/jenkins_home/helm/backend"  // ou frontend
}
```

- NEXUS_URL pointe vers le port Docker du registre (pas 8081 l'UI)
- KUBECONFIG indique a kubectl/helm ou trouver la config du cluster
- HELM_CHART pointe vers le chart copie en avance dans Jenkins

### 9.3 Stages detailles

**Stage 1 — Checkout**
```groovy
git branch: 'main', url: "${GITEA_URL}/vagrant/backend.git"
```
- Clone le repo depuis Gitea local
- Organisation "vagrant" dans Gitea
- Branche main par defaut

**Stage 2 — Build Image**
```groovy
sh "docker build -t ${NEXUS_URL}/${IMAGE_NAME}:${BUILD_NUMBER} ."
```
- Construit l'image Docker depuis le Dockerfile du repo
- Tag avec BUILD_NUMBER (incrementel, unique par build Jenkins)
- Docker est accessible via le socket monte dans le conteneur Jenkins

**Stage 3 — Push to Nexus**
```groovy
withCredentials([usernamePassword(
    credentialsId: 'nexus-credentials',
    usernameVariable: 'NEXUS_USER',
    passwordVariable: 'NEXUS_PASS'
)]) {
    sh "echo ${NEXUS_PASS} | docker login ${NEXUS_URL} -u ${NEXUS_USER} --password-stdin"
    sh "docker push ${NEXUS_URL}/${IMAGE_NAME}:${BUILD_NUMBER}"
    sh "docker tag ... ${NEXUS_URL}/${IMAGE_NAME}:latest"
    sh "docker push ${NEXUS_URL}/${IMAGE_NAME}:latest"
}
```
Pourquoi :
- withCredentials injecte les identifiants Nexus de maniere securisee
- Credential ID `nexus-credentials` doit etre configure dans Jenkins (Manage Credentials)
- Deux tags pushes : BUILD_NUMBER (immutable, tracable) et latest (pour le deploiement par defaut)
- --password-stdin evite de passer le mot de passe en argument CLI (visible dans ps)

**Stage 4 — Copy Helm Chart**
```groovy
sh "mkdir -p /var/jenkins_home/helm"
sh "cp -r helm/backend /var/jenkins_home/helm/"
```
Pourquoi :
- Les charts Helm sont copies depuis le repo Git vers un emplacement persistant dans Jenkins
- Cela permet un deploiement meme si le workspace est nettoye

**Stage 5 — Deploy**
```groovy
sh "helm upgrade --install ${HELM_RELEASE} ${HELM_CHART} --set image.tag=${BUILD_NUMBER} --namespace default"
```
Pourquoi :
- upgrade --install : cree la release si elle n'existe pas, la met a jour sinon
- --set image.tag=${BUILD_NUMBER} surcharge la valeur du tag dans values.yaml
- Kubernetes effectue un rolling update automatique quand l'image change

**Stage 6 — Verify**
```groovy
sh "kubectl rollout status deployment/${HELM_RELEASE} --timeout=120s"
```
Pourquoi :
- Attend que le rolling update soit termine et que tous les pods soient Ready
- Timeout 120s pour couvrir le pull de l'image + demarrage + readinessProbe
- Si le rollout echoue, le stage echoue et le build est marque FAILURE

### 9.4 Post-build cleanup

```groovy
post {
    always {
        sh "docker rmi ${NEXUS_URL}/${IMAGE_NAME}:${BUILD_NUMBER} || true"
        sh "docker rmi ${NEXUS_URL}/${IMAGE_NAME}:latest || true"
    }
}
```
Pourquoi :
- Supprime les images locales apres push pour eviter l'accumulation
- || true ignore les erreurs si l'image n'existe plus
- always s'execute quel que soit le resultat du build (success ou failure)

---

## 10. Script jenkins-kubectl-setup.sh — Injection kubectl et helm

### 10.1 Objectif

Donner au conteneur Jenkins la capacite d'interagir avec le cluster Kubernetes.

### 10.2 Implementation

**Etape 1 — Extraction kubeconfig**
```bash
ssh -o StrictHostKeyChecking=no vagrant@${MASTER_IP} "cat ~/.kube/config" > /tmp/k8s-config
```
- Le kubeconfig est genere par kubeadm init sur le master
- Il contient le certificat CA, le certificat client et la cle privee

**Etape 2 — Remplacement adresse serveur**
```bash
sed -i "s/127.0.0.1/${MASTER_IP}/g" /tmp/k8s-config
sed -i "s/localhost/${MASTER_IP}/g" /tmp/k8s-config
```
Pourquoi :
- Le kubeconfig pointe vers 127.0.0.1:6443 par defaut (pour usage local sur le master)
- Depuis Jenkins (VM services), il faut atteindre le master via son IP privee 192.168.56.10

**Etape 3 — Copie dans Jenkins**
```bash
docker exec jenkins mkdir -p /var/jenkins_home/.kube
docker cp /tmp/k8s-config jenkins:/var/jenkins_home/.kube/config
docker exec jenkins chmod 600 /var/jenkins_home/.kube/config
```
- Le fichier doit etre dans /var/jenkins_home/.kube/config (variable KUBECONFIG dans le Jenkinsfile)
- chmod 600 : restriction stricte (lecture/ecriture uniquement par le proprietaire)

**Etape 4 — Installation kubectl**
```bash
docker exec -u root jenkins bash -c \
    "curl -LO https://dl.k8s.io/release/v1.29.2/bin/linux/amd64/kubectl && \
     install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
```
Pourquoi :
- Version 1.29.2 alignee avec la version du cluster Kubernetes
- -u root car l'installation dans /usr/local/bin necessite les privileges root
- Le binaire est telecharge directement depuis dl.k8s.io (pas de gestionnaire de paquets)

**Etape 5 — Installation Helm**
```bash
docker exec -u root jenkins bash -c \
    "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
```
Pourquoi :
- Le script officiel get-helm-3 detecte l'architecture et installe la derniere version stable
- Helm est necessaire pour les stages Deploy dans les Jenkinsfiles

**Etape 6 — Verification**
```bash
docker exec jenkins kubectl get nodes
```
- Confirme que kubectl depuis Jenkins peut atteindre le cluster
- Doit afficher les 3 noeuds (master + 2 workers) en Ready

---

## 11. Script deploy-stage3.sh — Orchestration du deploiement

### 11.1 Objectif

Automatiser l'upload de tous les fichiers Stage 3 vers la VM services et executer le deploiement.

### 11.2 Sequence d'execution

| Etape | Commande | But |
|-------|----------|-----|
| 1 | vagrant upload tasks/main.yml + handlers/main.yml | Upload du role Ansible services_stack |
| 2 | vagrant upload playbook.yml | Mise a jour du playbook |
| 3 | vagrant upload nexus-setup.sh + jenkins-kubectl-setup.sh | Upload des scripts |
| 4 | vagrant ssh services -c "chmod +x ..." | Rend les scripts executables |
| 5 | ansible-playbook --limit services | Execute le role services_stack |
| 6 | sleep 60 | Attente initialisation conteneurs |
| 7 | nexus-setup.sh | Configure Nexus (password + repo Docker) |
| 8 | jenkins-kubectl-setup.sh | Installe kubectl/helm dans Jenkins |

### 11.3 Commande vagrant upload

```bash
vagrant upload <source_local> <destination_vm> <nom_vm>
```
- Copie un fichier depuis l'hote Windows vers la VM cible
- Ne necessite pas scp ni rsync
- Les chemins destination doivent etre absolus dans la VM

---

## 12. Flux de communication reseau Stage 3

### 12.1 Ports exposes

| Service | VM | Port | Protocole | Acces |
|---------|-----|------|-----------|-------|
| Gitea Web | services | 3000 | HTTP | http://192.168.56.20:3000 |
| Gitea SSH | services | 2222 | SSH | git@192.168.56.20:2222 |
| Nexus UI | services | 8081 | HTTP | http://192.168.56.20:8081 |
| Nexus Docker | services | 8082 | HTTP | docker login 192.168.56.20:8082 |
| Jenkins | services | 8080 | HTTP | http://192.168.56.20:8080 |
| Jenkins Agent | services | 50000 | JNLP | Communication agents distants |
| Backend | workers | 30080 | HTTP | http://192.168.56.11:30080 |
| Frontend | workers | 30000 | HTTP | http://192.168.56.11:30000 |
| MySQL | cluster | 3306 | TCP | mysql-svc.default.svc (interne) |

### 12.2 Flux du pipeline CI/CD

```
1. Developpeur push code → Gitea (:3000)
2. Jenkins webhook declenche le build
3. Jenkins clone depuis Gitea (HTTP)
4. Jenkins build Docker image (via docker.sock)
5. Jenkins push image → Nexus Docker Registry (:8082)
6. Jenkins helm upgrade → API Server k8s-master (:6443)
7. kubelet pull image depuis Nexus (:8082) via insecure-registries
8. Pods demarrent, readinessProbe valide
9. Service NodePort expose l'application
```

### 12.3 Configuration insecure-registries sur les workers

Important : la configuration `insecure-registries` dans daemon.json est sur la VM services. Pour que les workers puissent pull depuis 192.168.56.20:8082, il faut aussi configurer containerd sur les noeuds K8s :
- Soit ajouter un role Ansible qui configure `/etc/containerd/config.toml` pour le registre insecure
- Soit configurer les workers manuellement

---

## 13. Commandes de verification Stage 3

### 13.1 Verification des conteneurs

```bash
# Status des 3 conteneurs Docker
vagrant ssh services -c "sudo docker ps"
# Attendu: gitea, nexus, jenkins tous Up

# Acces web Gitea
curl http://192.168.56.20:3000
# Attendu: HTTP 200, page d'installation Gitea

# Acces web Nexus
curl http://192.168.56.20:8081
# Attendu: HTTP 200, interface Nexus

# Docker Registry API
curl -u admin:admin123 http://192.168.56.20:8082/v2/_catalog
# Attendu: {"repositories":[]} (vide au debut)
```

### 13.2 Verification Jenkins

```bash
# Mot de passe initial Jenkins
vagrant ssh services -c "sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"

# kubectl depuis Jenkins
vagrant ssh services -c "sudo docker exec jenkins kubectl get nodes"
# Attendu: 3 nodes Ready

# Helm depuis Jenkins
vagrant ssh services -c "sudo docker exec jenkins helm version"
# Attendu: version.BuildInfo{Version:"v3.x.y"...}
```

### 13.3 Verification cluster apres deploiement

```bash
# Pods deployes
vagrant ssh k8s-master -c "kubectl get pods -o wide"
# Attendu: 2 backend pods + 2 frontend pods Running

# Services NodePort
vagrant ssh k8s-master -c "kubectl get svc"
# Attendu: backend NodePort 30080, frontend NodePort 30000

# Test applicatif
curl http://192.168.56.11:30080/api/health
# Attendu: {"status":"ok"}

curl http://192.168.56.11:30000
# Attendu: page HTML React
```

---

## 14. Procedure d'execution complete (pas-a-pas)

```
1. vagrant up --no-provision              ← demarrer les VMs
2. Verifier cluster K8s                   ← kubectl get nodes (3 Ready)
3. Upload role services_stack             ← vagrant upload (tasks + handlers)
4. Upload playbook.yml                    ← vagrant upload
5. ansible-playbook --limit services      ← installe Docker + conteneurs
6. Attendre ~60s                          ← initialisation conteneurs
7. nexus-setup.sh                         ← configure Nexus (password + repo)
8. jenkins-kubectl-setup.sh               ← kubectl + helm dans Jenkins
9. Uploader Helm charts dans Jenkins      ← docker cp via vagrant ssh
10. Acceder aux interfaces web            ← verifier Gitea, Nexus, Jenkins
```

---

## 15. Resume des composants et leur role

| Composant | Role dans la chaine |
|-----------|---------------------|
| Gitea | Depot Git prive — heberge le code source backend/frontend |
| Nexus | Registre Docker prive — stocke les images construites |
| Jenkins | Serveur CI/CD — orchestre build, push, deploy |
| Docker | Moteur de conteneurisation — build les images |
| Dockerfile | Definition de l'image — etapes de construction |
| Helm | Gestionnaire de deploiement K8s — templates + values |
| Jenkinsfile | Definition du pipeline — stages CI/CD |
| kubectl | Client K8s — verification du deploiement |
| nginx.conf | Reverse proxy — route /api/ vers le backend |
| daemon.json | Config Docker — autorise registre Nexus sans TLS |
| kubeconfig | Credentials K8s — authentification au cluster |
| NodePort | Service K8s — expose l'application hors du cluster |
| readinessProbe | Health check K8s — valide que l'app est prete |
| mysql-secret | Secret K8s — injecte les credentials MySQL |


1. Dev push code → Gitea
2. Jenkins déclenche automatiquement
3. Jenkins build image Docker
4. Jenkins push image → Nexus
5. Jenkins déploie via Helm → Kubernetes
6. Pods se mettent à jour automatiquement
