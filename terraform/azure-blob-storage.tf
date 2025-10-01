# Azure Blob Storage for large data files (dera_zips)
# Alternative to Git LFS for files > 100 MB

# Storage Account for data files
resource "azurerm_storage_account" "data_storage" {
  name                     = "st${var.project_name}${random_id.instance_id.hex}"
  resource_group_name      = data.azurerm_resource_group.main.name
  location                 = data.azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS" # Locally Redundant Storage
  
  # Allow public access to blobs (for downloading in containers)
  allow_nested_items_to_be_public = true

  tags = {
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "data-files"
  }
}

# Container for dera_zips
resource "azurerm_storage_container" "dera_zips" {
  name                  = "dera-zips"
  storage_account_name  = azurerm_storage_account.data_storage.name
  container_access_type = "blob" # Public read access for blobs
}

# Container for dbt seeds (optional, if needed later)
resource "azurerm_storage_container" "dbt_seeds" {
  name                  = "dbt-seeds"
  storage_account_name  = azurerm_storage_account.data_storage.name
  container_access_type = "blob"
}

# Note: Files must be uploaded manually or via Azure CLI:
# az storage blob upload --account-name <storage_account_name> \
#   --container-name dera-zips \
#   --name 2024q4.zip \
#   --file ./dera_zips/2024q4.zip \
#   --auth-mode login

# Generate SAS token for secure access (optional, for private access)
data "azurerm_storage_account_sas" "data_sas" {
  connection_string = azurerm_storage_account.data_storage.primary_connection_string
  https_only        = true
  signed_version    = "2017-07-29"

  resource_types {
    service   = false
    container = false
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  start  = timestamp()
  expiry = timeadd(timestamp(), "8760h") # 1 year

  permissions {
    read    = true
    write   = false
    delete  = false
    list    = false
    add     = false
    create  = false
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}

# Output storage URLs for use in entrypoint script
output "azure_storage_account_name" {
  value       = azurerm_storage_account.data_storage.name
  description = "Azure Storage Account name for data files"
}

output "dera_zips_blob_url" {
  value       = "https://${azurerm_storage_account.data_storage.name}.blob.core.windows.net/dera-zips/2024q4.zip"
  description = "Public URL for dera_zips/2024q4.zip"
}

output "dbt_seeds_container_url" {
  value       = "https://${azurerm_storage_account.data_storage.name}.blob.core.windows.net/dbt-seeds"
  description = "Base URL for dbt seeds container"
}

