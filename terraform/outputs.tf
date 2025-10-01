output "resource_group_name" {
  description = "The name of the resource group"
  value       = data.azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  description = "The name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_cluster_id" {
  description = "The ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "acr_name" {
  description = "The name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "acr_login_server" {
  description = "The login server of the Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "acr_admin_username" {
  description = "The admin username for Azure Container Registry"
  value       = azurerm_container_registry.main.admin_username
  sensitive   = true
}

output "acr_admin_password" {
  description = "The admin password for Azure Container Registry"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

output "ingress_public_ip" {
  description = "The public IP address for the ingress"
  value       = azurerm_public_ip.ingress.ip_address
}

output "openmetadata_url" {
  description = "The URL for OpenMetadata"
  value       = "http://${azurerm_public_ip.ingress.ip_address}/openmetadata"
}

output "n8n_url" {
  description = "The URL for n8n"
  value       = "http://${azurerm_public_ip.ingress.ip_address}/api"
}

output "kube_config" {
  description = "Kubernetes config for kubectl"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "az aks get-credentials --resource-group ${data.azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}

output "docker_build_push_commands" {
  description = "Commands to build and push Docker images"
  value = <<-EOT
    # Login to ACR
    az acr login --name ${azurerm_container_registry.main.name}
    
    # Build and push Python Init image
    docker build -f Dockerfile.python-init -t ${azurerm_container_registry.main.login_server}/python-init:latest .
    docker push ${azurerm_container_registry.main.login_server}/python-init:latest
    
    # Build and push n8n image
    docker build -f Dockerfile.n8n-dbt -t ${azurerm_container_registry.main.login_server}/n8n-dbt:latest .
    docker push ${azurerm_container_registry.main.login_server}/n8n-dbt:latest
  EOT
}

output "deployment_info" {
  description = "Deployment information"
  value = {
    cluster_name  = azurerm_kubernetes_cluster.main.name
    namespace     = kubernetes_namespace.main.metadata[0].name
    ingress_ip    = azurerm_public_ip.ingress.ip_address
    openmetadata  = "http://${azurerm_public_ip.ingress.ip_address}/openmetadata"
    n8n           = "http://${azurerm_public_ip.ingress.ip_address}/api"
  }
}

# Output upload commands for large data files
output "upload_data_files_commands" {
  description = "Commands to upload large data files to Azure Blob Storage"
  value = <<-EOT
    # Upload dera_zips/2024q4.zip (118 MB)
    az storage blob upload \
      --account-name ${azurerm_storage_account.data_storage.name} \
      --container-name dera-zips \
      --name 2024q4.zip \
      --file ./dera_zips/2024q4.zip \
      --auth-mode login
    
    # Optional: Upload dbt seeds (if you want them in blob storage too)
    az storage blob upload-batch \
      --account-name ${azurerm_storage_account.data_storage.name} \
      --destination dbt-seeds \
      --source ./dbt/dera_dbt/seeds \
      --auth-mode login
    
    # Verify uploads
    az storage blob list \
      --account-name ${azurerm_storage_account.data_storage.name} \
      --container-name dera-zips \
      --output table \
      --auth-mode login
  EOT
}

