# AKS Deployment Guide - OpenMetadata mit Helm Charts

Folgt der offiziellen OpenMetadata Dokumentation: https://docs.open-metadata.org/latest/deployment/kubernetes/aks

## 🏗️ Architektur

```
AKS Cluster (rg-rshackathon-team10)
├── Namespace: openmetadata
│   ├── OpenMetadata (Helm Chart)
│   │   ├── OpenMetadata Server (Port 8585)
│   │   ├── MySQL (Metadata Store)
│   │   ├── Elasticsearch (Search)
│   │   └── Airflow (Ingestion)
│   ├── n8n (Docker Container)
│   └── Python Init Container (Git + Make + DBT)
│
└── Load Balancer (Public IP)
```

## 🚀 Deployment Schritte

### 1. Terraform Apply (AKS + Helm)

```bash
cd terraform
terraform init
terraform apply
```

**Was wird erstellt:**
- ✅ AKS Cluster
- ✅ Container Registry
- ✅ Virtual Network + Subnet
- ✅ Kubernetes Namespace "openmetadata"
- ✅ Azure File Storage Class (für Airflow PVCs)
- ✅ Persistent Volume Claims (airflow-dags, airflow-logs)
- ✅ Permissions Job (fix Airflow volume ownership)
- ✅ OpenMetadata Dependencies (Helm Chart)
  - MySQL
  - Elasticsearch
  - Airflow
- ✅ OpenMetadata Application (Helm Chart)
- ✅ Git SSH Key Secret
- ✅ ConfigMap für Environment Variables

### 2. Kubectl konfigurieren

```bash
az aks get-credentials --resource-group rg-rshackathon-team10 --name aks-openmetadata-aks
```

### 3. Status prüfen

```bash
# Alle Pods
kubectl get pods -n openmetadata

# OpenMetadata Pods
kubectl get pods -n openmetadata -l app.kubernetes.io/name=openmetadata

# Services
kubectl get svc -n openmetadata

# Helm Releases
helm list -n openmetadata
```

### 4. n8n und Python Container deployen

**n8n Deployment:**
```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: n8n
  namespace: openmetadata
spec:
  replicas: 1
  selector:
    matchLabels:
      app: n8n
  template:
    metadata:
      labels:
        app: n8n
    spec:
      containers:
      - name: n8n
        image: acropenmetadataaks9cf93bc1.azurecr.io/n8n-dbt:latest
        ports:
        - containerPort: 5678
        env:
        - name: N8N_BASIC_AUTH_ACTIVE
          value: "true"
        - name: N8N_BASIC_AUTH_USER
          value: "admin"
        - name: N8N_BASIC_AUTH_PASSWORD
          value: "change_me"
---
apiVersion: v1
kind: Service
metadata:
  name: n8n
  namespace: openmetadata
spec:
  selector:
    app: n8n
  ports:
  - port: 5678
    targetPort: 5678
EOF
```

**Python Init Container:**
```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: python-init
  namespace: openmetadata
spec:
  replicas: 1
  selector:
    matchLabels:
      app: python-init
  template:
    metadata:
      labels:
        app: python-init
    spec:
      containers:
      - name: python-init
        image: acropenmetadataaks9cf93bc1.azurecr.io/python-init:latest
        envFrom:
        - configMapRef:
            name: app-config
        volumeMounts:
        - name: git-ssh-key
          mountPath: /root/.ssh
          readOnly: true
      volumes:
      - name: git-ssh-key
        secret:
          secretName: git-ssh-key
          defaultMode: 0600
EOF
```

### 5. Ingress Controller installieren

```bash
# NGINX Ingress Controller via Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace openmetadata \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz
```

### 6. Ingress Resource erstellen

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: main-ingress
  namespace: openmetadata
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /\$2
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /openmetadata(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: openmetadata
            port:
              number: 8585
      - path: /api(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: n8n
            port:
              number: 5678
EOF
```

### 7. Public IP holen

```bash
# Warte bis LoadBalancer IP verfügbar ist (kann 10-15 Minuten dauern)
kubectl get svc ingress-nginx-controller -n openmetadata --watch

# Hole die IP
INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n openmetadata -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "OpenMetadata: http://$INGRESS_IP/openmetadata"
echo "n8n: http://$INGRESS_IP/api"
```

## 🐛 Troubleshooting

### OpenMetadata Pods starten nicht

```bash
# Logs ansehen
kubectl logs -n openmetadata -l app.kubernetes.io/name=openmetadata

# Pod beschreiben
kubectl describe pod -n openmetadata <pod-name>

# MySQL Status prüfen
kubectl logs -n openmetadata openmetadata-dependencies-mysql-0
```

### Airflow Permissions Problem

```bash
# Prüfe ob Permissions Job erfolgreich war
kubectl get job airflow-permissions-job -n openmetadata

# Logs ansehen
kubectl logs job/airflow-permissions-job -n openmetadata
```

### Helm Release Probleme

```bash
# Helm Status
helm status openmetadata-dependencies -n openmetadata
helm status openmetadata -n openmetadata

# Helm History
helm history openmetadata -n openmetadata

# Rollback falls nötig
helm rollback openmetadata 1 -n openmetadata
```

## 🔧 Nützliche Befehle

### Port-Forward für direkten Zugriff

```bash
# OpenMetadata
kubectl port-forward -n openmetadata svc/openmetadata 8585:8585

# n8n
kubectl port-forward -n openmetadata svc/n8n 5678:5678

# Airflow
kubectl port-forward -n openmetadata svc/openmetadata-dependencies-airflow-web 8080:8080
```

### Logs ansehen

```bash
# Alle Logs
kubectl logs -f -n openmetadata --all-containers=true

# Specific Service
kubectl logs -f -n openmetadata -l app.kubernetes.io/name=openmetadata
```

### Secrets und ConfigMaps

```bash
# Git SSH Key
kubectl get secret git-ssh-key -n openmetadata -o yaml

# MySQL Secrets
kubectl get secret mysql-secrets -n openmetadata -o yaml

# ConfigMap
kubectl get configmap app-config -n openmetadata -o yaml
```

## 📊 OpenMetadata Zugriff

### Default Admin Credentials

- **Username**: `admin`
- **Password**: `admin`

**⚠️ Wichtig**: Ändern Sie das Passwort nach dem ersten Login!

### Datenbank Verbindungen

OpenMetadata verwendet intern:
- **MySQL**: `openmetadata-dependencies-mysql:3306`
- **Elasticsearch**: `openmetadata-dependencies-elasticsearch:9200`
- **Airflow**: `http://openmetadata-dependencies-airflow-web:8080`

## 🧹 Cleanup

### Helm Releases löschen

```bash
helm uninstall openmetadata -n openmetadata
helm uninstall openmetadata-dependencies -n openmetadata
helm uninstall ingress-nginx -n openmetadata
```

### Namespace löschen

```bash
kubectl delete namespace openmetadata
```

### Terraform Ressourcen löschen

```bash
cd terraform
terraform destroy
```

## 📚 Weitere Ressourcen

- [OpenMetadata AKS Dokumentation](https://docs.open-metadata.org/latest/deployment/kubernetes/aks)
- [OpenMetadata Helm Charts](https://github.com/open-metadata/openmetadata-helm-charts)
- [Airflow Helm Chart](https://airflow.apache.org/docs/helm-chart/)

