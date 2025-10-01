terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.main.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.main.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate)
  }
}

# Random ID for unique naming
resource "random_id" "instance_id" {
  byte_length = 4
}

# Use existing Resource Group
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# Virtual Network for AKS
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.project_name}"
  address_space       = ["10.0.0.0/8"]
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Subnet for AKS
resource "azurerm_subnet" "aks" {
  name                 = "subnet-aks"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.240.0.0/16"]
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${var.project_name}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  dns_prefix          = "aks-${var.project_name}"

  default_node_pool {
    name                = "default"
    node_count          = var.node_count
    vm_size             = var.node_vm_size
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = true
    min_count           = var.node_min_count
    max_count           = var.node_max_count
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin     = "azure"
    network_policy     = "azure"
    service_cidr       = "10.0.0.0/16"
    dns_service_ip     = "10.0.0.10"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Container Registry (for custom images)
resource "azurerm_container_registry" "main" {
  name                = "acr${replace(var.project_name, "-", "")}${random_id.instance_id.hex}"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  sku                 = var.acr_sku
  admin_enabled       = true

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Attach ACR to AKS
resource "azurerm_role_assignment" "aks_acr" {
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.main.id
  skip_service_principal_aad_check = true
}

# Public IP for Ingress
resource "azurerm_public_ip" "ingress" {
  name                = "pip-ingress"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Kubernetes Namespace
resource "kubernetes_namespace" "main" {
  metadata {
    name = var.k8s_namespace
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}

# Kubernetes Secret for Git SSH Key
resource "kubernetes_secret" "git_ssh_key" {
  metadata {
    name      = "git-ssh-key"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  data = {
    git_deploy_key = file("${path.module}/git-deploy-key")
    config = <<-EOT
      Host github.com
          HostName github.com
          User git
          IdentityFile /root/.ssh/git_deploy_key
          IdentitiesOnly yes
          StrictHostKeyChecking no
    EOT
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.main]
}

# Kubernetes ConfigMap for Environment Variables
resource "kubernetes_config_map" "app_config" {
  metadata {
    name      = "app-config"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  data = {
    # OpenMetadata Configuration
    OM_API                    = "http://openmetadata-server:8585/api"
    OPENMETADATA_CLUSTER_NAME = "openmetadata"
    SERVER_PORT               = "8585"
    SERVER_ADMIN_PORT         = "8586"
    
    # PostgreSQL Configuration
    PGHOST                    = "postgres"
    PGPORT                    = "5432"
    PGDATABASE                = "dera"
    PGUSER                    = "dbt"
    PGPASSWORD                = "dbt"
    
    # MySQL Configuration (for OpenMetadata)
    DB_HOST                   = "mysql"
    DB_PORT                   = "3306"
    DB_USER                   = "openmetadata_user"
    DB_USER_PASSWORD          = "openmetadata_password"
    OM_DATABASE               = "openmetadata_db"
    
    # Elasticsearch Configuration
    ELASTICSEARCH_HOST        = "elasticsearch"
    ELASTICSEARCH_PORT        = "9200"
    ELASTICSEARCH_SCHEME      = "http"
    
    # Git Configuration
    GIT_REPO                  = var.repository_url
    GIT_BRANCH                = var.repository_branch
    
    # n8n Configuration
    N8N_BASIC_AUTH_ACTIVE     = "true"
    N8N_BASIC_AUTH_USER       = "admin"
    N8N_BASIC_AUTH_PASSWORD   = "change_me"
    
    # Azure Blob Storage URLs (set dynamically from azure-blob-storage.tf)
    AZURE_STORAGE_ACCOUNT     = try(azurerm_storage_account.data_storage.name, "")
    BLOB_BASE_URL             = try("https://${azurerm_storage_account.data_storage.name}.blob.core.windows.net", "")
    DERA_ZIPS_URL             = try("https://${azurerm_storage_account.data_storage.name}.blob.core.windows.net/dera-zips/2024q4.zip", "")
    DBT_SEEDS_URL             = try("https://${azurerm_storage_account.data_storage.name}.blob.core.windows.net/dbt-seeds", "")
  }

  depends_on = [kubernetes_namespace.main]
}

# Note: LoadBalancer Service removed - will be created by Helm/Ingress Controller manually
# This avoids the 20+ minute timeout issue with Terraform

