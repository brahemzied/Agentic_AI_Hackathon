variable "resource_group_name" {
  description = "The name of the existing resource group to use"
  type        = string
  default     = "rg-rshackathon-team10"
}

variable "project_name" {
  description = "The name of the project"
  type        = string
  default     = "openmetadata-aks"
}

variable "location" {
  description = "The Azure location/region (from existing RG)"
  type        = string
  default     = "westeurope"
}

variable "environment" {
  description = "The environment name"
  type        = string
  default     = "production"
}

# AKS Configuration
variable "node_count" {
  description = "Initial number of nodes in the AKS cluster"
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "The size of the VM for AKS nodes"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "node_min_count" {
  description = "Minimum number of nodes for autoscaling"
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "Maximum number of nodes for autoscaling"
  type        = number
  default     = 5
}

# Container Registry Configuration
variable "acr_sku" {
  description = "The SKU for Azure Container Registry"
  type        = string
  default     = "Basic"
}

# Kubernetes Configuration
variable "k8s_namespace" {
  description = "Kubernetes namespace for the application"
  type        = string
  default     = "openmetadata"
}

# Repository Configuration
variable "repository_url" {
  description = "GitHub repository URL to clone"
  type        = string
  default     = "git@github.com:brahemzied/Agentic_AI_Hackathon.git"
}

variable "repository_branch" {
  description = "Git branch to checkout"
  type        = string
  default     = "QS"
}

