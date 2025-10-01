# AKS Deployment für OpenMetadata + n8n

Dieses Terraform Setup erstellt eine Azure Kubernetes Service (AKS) Umgebung für OpenMetadata und n8n.

## 📋 Architektur

```
Internet → Load Balancer (Public IP) → Ingress Controller
                                           ├── /openmetadata → OpenMetadata (8585)
                                           └── /api → n8n (5678)

AKS Cluster:
├── Namespace: openmetadata
├── Python Init Container (Git + Make + DBT)
├── OpenMetadata Container
├── n8n Container
├── PostgreSQL Container
├── MySQL Container (für OpenMetadata)
└── Elasticsearch Container
```

## 🚀 Deployment Schritte

### 1. Voraussetzungen

```bash
# Azure CLI installiert
az --version

# Terraform installiert
terraform --version

# kubectl installiert
kubectl version --client

# Docker installiert
docker --version
```

### 2. Azure Login

```bash
az login --use-device-code
```

### 3. Terraform Konfiguration

```bash
cd terraform

# Kopiere die Beispiel-Konfiguration
cp terraform.tfvars.example.new terraform.tfvars

# Bearbeite terraform.tfvars mit deinen Werten
nano terraform.tfvars
```

### 4. Terraform Deployment

```bash
# Initialisiere Terraform
terraform init

# Plane das Deployment
terraform plan

# Deploye die Infrastruktur
terraform apply -auto-approve
```

**Wichtig:** Dies erstellt:
- AKS Cluster (kann 10-15 Minuten dauern)
- Container Registry
- Virtual Network
- Load Balancer mit Public IP

### 5. Kubectl Konfiguration

```bash
# Hole die AKS Credentials
az aks get-credentials \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw aks_cluster_name)

# Teste die Verbindung
kubectl get nodes
kubectl get namespaces
```

### 6. Docker Images bauen und pushen

```bash
# Login zur Azure Container Registry
az acr login --name $(terraform output -raw acr_name)

# Baue Python Init Image
docker build -f Dockerfile.python-init \
  -t $(terraform output -raw acr_login_server)/python-init:latest .

docker push $(terraform output -raw acr_login_server)/python-init:latest

# Baue n8n Image
docker build -f Dockerfile.n8n-dbt \
  -t $(terraform output -raw acr_login_server)/n8n-dbt:latest .

docker push $(terraform output -raw acr_login_server)/n8n-dbt:latest
```

### 7. Konvertiere Docker Compose zu Kubernetes

```bash
# Installiere kompose (falls nicht vorhanden)
curl -L https://github.com/kubernetes/kompose/releases/download/v1.31.2/kompose-linux-amd64 -o kompose
chmod +x kompose
sudo mv kompose /usr/local/bin/

# Konvertiere docker-compose.yml
kompose convert -f docker-compose.yml -o k8s/

# Passe die generierten Manifeste an (verwende ACR Images)
# Bearbeite k8s/*.yaml Dateien und ersetze Images mit ACR URLs
```

### 8. Deploye die Applikation

```bash
# Deploye alle Services
kubectl apply -f k8s/ -n openmetadata

# Checke den Status
kubectl get pods -n openmetadata
kubectl get services -n openmetadata
```

### 9. Zugriff auf die Applikation

```bash
# Hole die Public IP
INGRESS_IP=$(terraform output -raw ingress_public_ip)

echo "OpenMetadata: http://${INGRESS_IP}/openmetadata"
echo "n8n: http://${INGRESS_IP}/api"

# Oder benutze die Outputs
terraform output openmetadata_url
terraform output n8n_url
```

## 🔧 Nützliche Befehle

### Logs ansehen

```bash
# Alle Pods
kubectl logs -f -n openmetadata --all-containers=true

# Specific Pod
kubectl logs -f -n openmetadata python-init-xxx

# OpenMetadata Logs
kubectl logs -f -n openmetadata openmetadata-server-xxx
```

### Pod Status

```bash
# Alle Pods im Namespace
kubectl get pods -n openmetadata

# Detaillierte Pod-Info
kubectl describe pod -n openmetadata python-init-xxx

# In einen Pod einsteigen
kubectl exec -it -n openmetadata python-init-xxx -- /bin/bash
```

### Services und Ingress

```bash
# Services
kubectl get services -n openmetadata

# Ingress
kubectl get ingress -n openmetadata

# Load Balancer IP
kubectl get svc ingress-nginx-controller -n openmetadata
```

### Secrets und ConfigMaps

```bash
# Git SSH Key Secret
kubectl get secret git-ssh-key -n openmetadata -o yaml

# App Config
kubectl get configmap app-config -n openmetadata -o yaml
```

## 🐛 Troubleshooting

### Pods starten nicht

```bash
# Events ansehen
kubectl get events -n openmetadata --sort-by='.lastTimestamp'

# Pod Beschreibung
kubectl describe pod -n openmetadata <pod-name>

# Logs ansehen
kubectl logs -n openmetadata <pod-name> --previous
```

### Image Pull Fehler

```bash
# Checke ACR Zugriff
az acr repository list --name $(terraform output -raw acr_name)

# Checke AKS-ACR Verbindung
kubectl get secret -n openmetadata
```

### Service nicht erreichbar

```bash
# Port-Forward für direkten Zugriff
kubectl port-forward -n openmetadata svc/openmetadata-server 8585:8585

# Dann: http://localhost:8585
```

## 🧹 Cleanup

### Applikation löschen

```bash
kubectl delete namespace openmetadata
```

### Infrastruktur löschen

```bash
terraform destroy -auto-approve
```

## 📊 Kosten

**Geschätzte monatliche Kosten (West Europe):**
- AKS Cluster (2x Standard_D4s_v3): ~€280/Monat
- Load Balancer: ~€20/Monat
- Public IP: ~€3/Monat
- ACR Basic: ~€4/Monat
- **Total: ~€307/Monat**

**Kosteneinsparung:**
- Skaliere auf 1 Node wenn nicht benötigt
- Verwende Spot Instances
- Stop das Cluster nachts (dev/test)

## 🔐 Sicherheit

### Secrets Management

Die SSH Keys werden als Kubernetes Secrets gespeichert:

```bash
# Secret erstellen (automatisch via Terraform)
kubectl create secret generic git-ssh-key \
  --from-file=git_deploy_key=./terraform/git-deploy-key \
  --from-file=config=./ssh-config \
  -n openmetadata
```

### Network Policies

Empfohlen: Verwende Network Policies um Traffic zwischen Pods zu kontrollieren.

## 📚 Weitere Ressourcen

- [AKS Documentation](https://docs.microsoft.com/en-us/azure/aks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Kompose Documentation](https://kompose.io/)

