# Azure Blob Storage - Data Files Upload

Große Dateien (> 100 MB) werden in **Azure Blob Storage** gespeichert statt in Git.

## 📦 Betroffene Dateien

### 1. `dera_zips/2024q4.zip` - **118 MB**
- ❌ Zu groß für Git (Limit: 100 MB)
- ✅ Wird in Azure Blob Storage `dera-zips` Container gespeichert
- 📥 Wird automatisch vom `python-init` Container heruntergeladen

### 2. `dbt/dera_dbt/seeds/*.csv` - **75 MB total**
- ✅ Klein genug für Git
- Optional: Kann auch in Blob Storage gelegt werden

## 🚀 Upload nach Terraform Deployment

### Schritt 1: Terraform Apply
```bash
cd terraform
terraform apply
```

### Schritt 2: Upload Commands holen
```bash
terraform output -raw upload_data_files_commands
```

Dies gibt Ihnen die fertigen Befehle mit dem korrekten Storage Account Namen.

### Schritt 3: Dateien hochladen

#### Nur dera_zips (empfohlen)
```bash
# Hole Storage Account Name
STORAGE_ACCOUNT=$(terraform output -raw azure_storage_account_name)

# Upload 2024q4.zip
az storage blob upload \
  --account-name $STORAGE_ACCOUNT \
  --container-name dera-zips \
  --name 2024q4.zip \
  --file ../dera_zips/2024q4.zip \
  --auth-mode login

# Verify
az storage blob list \
  --account-name $STORAGE_ACCOUNT \
  --container-name dera-zips \
  --output table \
  --auth-mode login
```

#### Optional: DBT Seeds auch hochladen
```bash
# Upload alle seed files
az storage blob upload-batch \
  --account-name $STORAGE_ACCOUNT \
  --destination dbt-seeds \
  --source ../dbt/dera_dbt/seeds \
  --auth-mode login

# Verify
az storage blob list \
  --account-name $STORAGE_ACCOUNT \
  --container-name dbt-seeds \
  --output table \
  --auth-mode login
```

## 🔍 Verify Download im Container

Nach dem Deployment können Sie prüfen, ob die Dateien korrekt heruntergeladen wurden:

```bash
# Hole kubectl config
az aks get-credentials --resource-group rg-rshackathon-team10 --name aks-openmetadata-aks

# Prüfe python-init Container Logs
kubectl logs -n openmetadata -l app=python-init | grep "Downloading"

# Exec in Container und prüfe Dateien
kubectl exec -n openmetadata -it deployment/python-init -- bash
ls -lh /workspace/dera_zips/
ls -lh /workspace/dbt/dera_dbt/seeds/
```

## 🌐 Public Access

Die Blobs sind **public readable** konfiguriert:
- ✅ Keine Authentifizierung nötig für Downloads
- ✅ Container sind vom Python Init Container aus direkt erreichbar
- ⚠️ URLs sind öffentlich, aber schwer zu erraten

### Beispiel URL:
```
https://stopenmetadataaks9cf93bc1.blob.core.windows.net/dera-zips/2024q4.zip
```

## 🔐 Private Access (Optional)

Falls Sie die Blobs privat halten möchten, ändern Sie in `azure-blob-storage.tf`:

```hcl
resource "azurerm_storage_container" "dera_zips" {
  name                  = "dera-zips"
  storage_account_name  = azurerm_storage_account.data_storage.name
  container_access_type = "private"  # Statt "blob"
}
```

Dann müssen Sie SAS Tokens verwenden:
```bash
# Generate SAS token
az storage blob generate-sas \
  --account-name $STORAGE_ACCOUNT \
  --container-name dera-zips \
  --name 2024q4.zip \
  --permissions r \
  --expiry 2025-12-31 \
  --auth-mode login \
  --as-user
```

## 📊 Kosten

Azure Blob Storage (Standard LRS):
- **Storage**: ~$0.02/GB/Monat
- **118 MB**: ~$0.0024/Monat (< 1 Cent!)
- **Egress**: Erste 100 GB/Monat kostenlos innerhalb Azure

## 🧹 Cleanup

Um die Storage Ressourcen zu löschen:

```bash
# Liste alle Blobs
az storage blob list \
  --account-name $STORAGE_ACCOUNT \
  --container-name dera-zips \
  --auth-mode login

# Lösche einzelne Blobs
az storage blob delete \
  --account-name $STORAGE_ACCOUNT \
  --container-name dera-zips \
  --name 2024q4.zip \
  --auth-mode login

# Oder: Terraform destroy löscht automatisch alles
cd terraform
terraform destroy
```

## ❓ Troubleshooting

### Fehler: "blob not found" im Container
```bash
# Prüfe, ob Blob existiert
az storage blob show \
  --account-name $STORAGE_ACCOUNT \
  --container-name dera-zips \
  --name 2024q4.zip \
  --auth-mode login

# Prüfe Container
az storage container show \
  --account-name $STORAGE_ACCOUNT \
  --name dera-zips \
  --auth-mode login
```

### Fehler: "AuthenticationFailed"
```bash
# Re-login
az login --use-device-code

# Oder verwende Storage Account Key
STORAGE_KEY=$(az storage account keys list \
  --account-name $STORAGE_ACCOUNT \
  --query '[0].value' -o tsv)

az storage blob upload \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY \
  --container-name dera-zips \
  --name 2024q4.zip \
  --file ../dera_zips/2024q4.zip
```

### Fehler: Container download schlägt fehl
```bash
# Test URL direkt
curl -I "https://$STORAGE_ACCOUNT.blob.core.windows.net/dera-zips/2024q4.zip"

# Sollte 200 OK zurückgeben
```

## 📚 Weitere Ressourcen

- [Azure Blob Storage Docs](https://docs.microsoft.com/en-us/azure/storage/blobs/)
- [Azure CLI Storage Commands](https://docs.microsoft.com/en-us/cli/azure/storage/blob)

