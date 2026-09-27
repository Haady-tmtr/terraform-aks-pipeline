# terraform-aks-pipeline
Infrastructure DevOps sur Azure - provisionnée en IaC, conteneurisée et déployée en CI/CD.


Projet de référence démontrant une chaîne complète Infrastructure-as-Code sur Azure : provisioning d'un cluster Kubernetes (AKS) et d'un registre de conteneurs (ACR) avec Terraform, containerisation d'une application Python minimale, et pipeline CI/CD GitHub Actions pour le build et le déploiement automatique - authentifié sans aucun secret stocké, via Workload Identity Federation (OIDC). L'accent est mis sur l'infrastructure et l'automatisation, pas sur la complexité applicative.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                        GitHub                                        │
│  push → GitHub Actions → OIDC (sans secret) → build image → push ACR │
│                              │                                       │
│                              ▼                                       │
│                     kubectl set image + rollout status               │
└──────────────────────────────┼───────────────────────────────────────┘
                               │  (Managed Identity + Federated Credential)
        ┌──────────────────────▼────────────────────────┐
        │        Azure (terraform-aks-pipeline-rg)      │
        │              région : swedencentral           │
        │                                               │
        │   ┌─────────────┐     ┌───────────────────┐   │
        │   │     ACR     │────▶│    AKS Cluster    │   │
        │   │terraformaks-│     │terraform-aks-     │   │
        │   │pipelineacr  │     │pipeline-aks       │   │
        │   └─────────────┘     │ (standard_b2as_v2)│   │
        │                       │  Pod 1 │  Pod 2   │   │
        │                       │  app   │  app     │   │
        │                       └────────┬──────────┘   │
        │                                │              │
        │                       LoadBalancer (IP pub)   │
        └────────────────────────────────┼──────────────┘
                                         │
                                    Navigateur
```

---

## Stack technique

| Outil | Rôle |
|---|---|
| Terraform | Provisioning IaC : Resource Group, AKS, ACR, Role Assignment |
| Azure AKS | Cluster Kubernetes managé (1 node, `standard_b2as_v2`) |
| Azure ACR | Registre Docker privé (stockage des images) |
| Python (Flask) | Application minimale, affiche le hostname du pod |
| Docker | Containerisation de l'application |
| Kubernetes | Deployment (2 replicas), Service LoadBalancer, probes de santé |
| GitHub Actions | Pipeline CI/CD : build -> push ACR -> déploiement AKS |
| Managed Identity + OIDC | Authentification du pipeline sans secret stocké (Workload Identity Federation) |

---

## Prérequis

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- [Azure CLI](https://learn.microsoft.com/fr-fr/cli/azure/install-azure-cli) installé et configuré (`az login`)
- [Docker](https://www.docker.com/products/docker-desktop/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installé
- Un compte Azure avec une subscription active
- Un repo GitHub

---

## Installation

### 1. Cloner le repo

```bash
git clone https://github.com/Haady-tmtr/terraform-aks-pipeline
cd terraform-aks-pipeline
```

### 2. Se connecter à Azure

```bash
az login --tenant <TENANT_ID>
az account set --subscription <SUBSCRIPTION_ID>
```

### 3. Provisionner l'infrastructure avec Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Durée estimée : ~5-10 minutes. À la fin, Terraform affiche les outputs :

```
acr_login_server    = "terraformakspipelineacr.azurecr.io"
aks_cluster_name    = "terraform-aks-pipeline-aks"
resource_group_name = "terraform-aks-pipeline-rg"
```

> **Note sur les quotas** : selon votre type de compte Azure (notamment Azure for Students),
> certaines régions ou tailles de VM peuvent être bloquées par des quotas vCPU nuls sur les
> séries récentes. Nous utilisons `swedencentral` avec une taille de nœud modeste(`standard_b2as_v2`). C'est la configuration validée dans ce projet.

### 4. Récupérer le kubeconfig

```bash
az aks get-credentials --resource-group terraform-aks-pipeline-rg --name terraform-aks-pipeline-aks
kubectl get nodes
```

Le node doit apparaître `Ready` en état.

### 5. Builder et pusher l'image Docker

```bash
cd ..
az acr login --name terraformakspipelineacr
docker build -t terraformakspipelineacr.azurecr.io/terraform-aks-pipeline-app:latest ./app
docker push terraformakspipelineacr.azurecr.io/terraform-aks-pipeline-app:latest
```

### 6. Déployer sur Kubernetes

```bash
kubectl apply -f k8s/
kubectl get pods
kubectl get svc terraform-aks-pipeline-app-svc
```

Attendez l'`EXTERNAL-IP` puis testez :
```bash
curl http://<EXTERNAL-IP>/
curl http://<EXTERNAL-IP>/health
```
Rafraîchissez plusieurs fois - le hostname affiché doit alterner entre les deux pods, preuve que le load balancing fonctionne.

---

## Pipeline CI/CD

Le pipeline GitHub Actions se déclenche automatiquement à chaque `push` sur `main` :

```
push → checkout → azure/login (OIDC) → az acr login → build image → push image
     → az aks get-credentials → kubectl set image → kubectl rollout status
```

Aucun secret Azure de type mot de passe/clé n'est stocké dans GitHub — l'authentification
passe par une **Managed Identity** avec un lien de confiance fédéré (Workload Identity
Federation), qui échange un token OIDC signé par GitHub contre un token d'accès Azure à
chaque exécution.

### Mise en place de l'authentification OIDC

**1. Créer une Managed Identity dédiée**
```bash
az identity create --resource-group terraform-aks-pipeline-rg --name terraform-aks-pipeline-github-mi
```

**2. Récupérer son `clientId` et `principalId`**
```bash
az identity show --resource-group terraform-aks-pipeline-rg --name terraform-aks-pipeline-github-mi \
  --query "{clientId:clientId, principalId:principalId}" -o json
```

**3. Lui attribuer le rôle Contributor sur le resource group**
```bash
az role assignment create \
  --assignee <principalId> \
  --role Contributor \
  --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/terraform-aks-pipeline-rg
```

**4. Récupérer les identifiants immuables de votre repo GitHub**

```bash
curl -s https://api.github.com/repos/<TON_ORG>/<TON_REPO> | jq '{owner_id: .owner.id, repo_id: .id}'
```

**5. Créer le lien de confiance fédéré**
```bash
az identity federated-credential create \
  --name "github-actions-terraform-aks-pipeline" \
  --identity-name terraform-aks-pipeline-github-mi \
  --resource-group terraform-aks-pipeline-rg \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:<TON_ORG>@<owner_id>/<TON_REPO>@<repo_id>:ref:refs/heads/main" \
  --audiences "api://AzureADTokenExchange"
```

### Secrets GitHub à configurer

Sur votre repo : `Settings` → `Secrets and variables` → `Actions` :

| Secret | Valeur |
|---|---|
| `AZURE_CLIENT_ID` | `clientId` de la Managed Identity (étape 2) |
| `AZURE_TENANT_ID` | Votre Tenant ID Azure |
| `AZURE_SUBSCRIPTION_ID` | Votre Subscription ID Azure |

Aucun mot de passe, aucune clé secrète à générer ni à faire tourner.

---

## Structure du projet

```
terraform-aks-pipeline/
├── .github/
│   └── workflows/
│       └── deploy.yml        # Pipeline CI/CD GitHub Actions
├── app/
│   ├── Dockerfile            
│   ├── main.py                # Application Flask (affiche le hostname du pod)
│   └── requirements.txt
├── k8s/
│   ├── deployment.yml        # Deployment 2 replicas, probes readiness/liveness
│   └── service.yml           # Service LoadBalancer
├── terraform/
│   ├── main.tf                
│   ├── provider.tf            
│   ├── variables.tf           
│   └── outputs.tf             
└── README.md
```

---

## Commandes utiles

```bash
# Voir les pods en cours
kubectl get pods

# Voir les logs d'un pod
kubectl logs <nom-du-pod>

# Vérifier le rollout
kubectl rollout status deployment/terraform-aks-pipeline-app

# Scaler le déploiement
kubectl scale deployment terraform-aks-pipeline-app --replicas=3

# Détruire toute l'infrastructure (pour éviter les frais)
cd terraform && terraform destroy
```

> La Managed-identity ayant été créee à la main, le `terraform destroy` peut refuser de détruire cette ressource à l'intérieur du resource-group. Donc détruire cette identité managée avant de relancer le destroy : 

```bash
# Destruction de la managed-identity
- az identity delete --resource-group terraform-aks-pipeline-rg --name terraform-aks-pipeline-github-mi

# Destruction finale de l'infrastructure
- terraform destroy -auto-approve
```

---

## Points techniques notables

**Authentification sans secret** : le pipeline utilise une Managed Identity Azure avec
Workload Identity Federation (OIDC) plutôt qu'un Service Principal classique. La subscription `Azure for Students` dans mon cas ne semble pas couvrir cette option. Aucun mot
de passe ni clé à stocker dans GitHub, aucun secret à faire tourner ou à sécuriser contre
une fuite.

**Format de subject immuable** : la configuration du federated credential utilise le
format `repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:...`, qui protège contre le recyclage
de nom de compte/dépôt — un renommage ou un transfert du repo ne casse pas la confiance
établie, contrairement à l'ancien format basé uniquement sur les noms.

**2 replicas** : le déploiement tourne avec 2 pods. En rafraîchissant la page, le hostname
affiché alterne entre les deux pods — preuve que le Service Kubernetes fait bien du load
balancing.

**Actions et images épinglées** : les actions GitHub sont épinglées par SHA de commit (pas
par tag mutable), et le runner utilise une version fixe (`ubuntu-24.04` plutôt que
`ubuntu-latest`) — évite qu'une mise à jour silencieuse en amont (compromission de tag,
changement de version du runner) casse ou compromette le pipeline sans qu'aucun commit
n'ait été poussé de notre côté.

**Résolution de blocages de quotas Azure** : le provisioning initial a rencontré plusieurs
blocages typiques d'un compte à quotas restreints (région `westeurope` non autorisée par
policy, quotas vCPU nuls sur les séries de VM récentes en `germanywestcentral`) — résolus
en basculant sur la région `swedencentral` avec une taille de nœud plus modeste
(`standard_b2as_v2`).

**`oidc_issuer_enabled`** : Azure active désormais l'émetteur OIDC par défaut sur les
nouveaux clusters AKS. Ce paramètre est déclaré explicitement dans `main.tf` pour éviter
que Terraform ne tente de le désactiver (opération refusée par l'API Azure, l'OIDC Issuer
d'un cluster AKS ne pouvant pas être désactivé une fois activé).

---

## Améliorations futures

- Ajouter une supervision (Prometheus/Grafana).
- Mettre en place un backend Terraform distant (Azure Storage) pour permettre le travail en équipe.
---