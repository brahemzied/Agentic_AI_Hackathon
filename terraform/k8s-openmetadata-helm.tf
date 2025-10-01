# OpenMetadata Helm Chart Installation
# Following official docs: https://docs.open-metadata.org/latest/deployment/kubernetes/aks

# Helm provider
terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.main.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate)
  }
}

# Step 1: Create Azure File Storage Class for Airflow PVCs
resource "kubernetes_storage_class" "azure_file" {
  metadata {
    name = "azurefile-csi"
  }

  storage_provisioner = "file.csi.azure.com"
  reclaim_policy      = "Retain"
  
  parameters = {
    skuName = "Standard_LRS"
  }

  mount_options = [
    "dir_mode=0777",
    "file_mode=0777",
    "uid=0",
    "gid=0",
    "mfsymlinks",
    "cache=strict",
    "actimeo=30"
  ]

  depends_on = [azurerm_kubernetes_cluster.main]
}

# Step 2: Create PVCs for Airflow
resource "kubernetes_persistent_volume_claim" "airflow_dags" {
  metadata {
    name      = "airflow-dags"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = kubernetes_storage_class.azure_file.metadata[0].name

    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }

  depends_on = [kubernetes_storage_class.azure_file]
}

resource "kubernetes_persistent_volume_claim" "airflow_logs" {
  metadata {
    name      = "airflow-logs"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = kubernetes_storage_class.azure_file.metadata[0].name

    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }

  depends_on = [kubernetes_storage_class.azure_file]
}

# Step 3: Fix Permissions Job for Airflow volumes
resource "kubernetes_job" "airflow_permissions" {
  metadata {
    name      = "airflow-permissions-job"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  spec {
    template {
      metadata {}

      spec {
        restart_policy = "Never"

        container {
          name    = "permissions-fix"
          image   = "busybox"
          command = ["/bin/sh", "-c"]
          args = [
            "chown -R 50000:0 /airflow-dags && chown -R 50000:0 /airflow-logs && chmod -R 775 /airflow-dags && chmod -R 775 /airflow-logs"
          ]

          volume_mount {
            name       = "airflow-dags"
            mount_path = "/airflow-dags"
          }

          volume_mount {
            name       = "airflow-logs"
            mount_path = "/airflow-logs"
          }
        }

        volume {
          name = "airflow-dags"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.airflow_dags.metadata[0].name
          }
        }

        volume {
          name = "airflow-logs"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.airflow_logs.metadata[0].name
          }
        }
      }
    }
  }

  wait_for_completion = true
  timeouts {
    create = "5m"
  }

  depends_on = [
    kubernetes_persistent_volume_claim.airflow_dags,
    kubernetes_persistent_volume_claim.airflow_logs
  ]
}

# Step 4: Add OpenMetadata Helm Repository
resource "helm_release" "openmetadata_dependencies" {
  name       = "openmetadata-dependencies"
  repository = "https://helm.open-metadata.org"
  chart      = "openmetadata-dependencies"
  version    = "1.9.11" # Match your OpenMetadata version
  namespace  = kubernetes_namespace.main.metadata[0].name

  timeout = 600

  # Use existing PVCs for Airflow
  values = [
    yamlencode({
      airflow = {
        airflow = {
          enabled = true
          config = {
            AIRFLOW__CORE__EXECUTOR = "LocalExecutor"
          }
        }
        dags = {
          persistence = {
            enabled          = true
            existingClaim    = kubernetes_persistent_volume_claim.airflow_dags.metadata[0].name
            storageClassName = kubernetes_storage_class.azure_file.metadata[0].name
          }
        }
        logs = {
          persistence = {
            enabled          = true
            existingClaim    = kubernetes_persistent_volume_claim.airflow_logs.metadata[0].name
            storageClassName = kubernetes_storage_class.azure_file.metadata[0].name
          }
        }
      }
      mysql = {
        enabled = true
        primary = {
          persistence = {
            enabled = true
            size    = "50Gi"
          }
        }
      }
      elasticsearch = {
        enabled   = true
        replicas  = 1
        resources = {
          requests = {
            memory = "1Gi"
            cpu    = "500m"
          }
        }
      }
    })
  ]

  depends_on = [kubernetes_job.airflow_permissions]
}

# Step 5: Install OpenMetadata
resource "helm_release" "openmetadata" {
  name       = "openmetadata"
  repository = "https://helm.open-metadata.org"
  chart      = "openmetadata"
  version    = "1.9.11"
  namespace  = kubernetes_namespace.main.metadata[0].name

  timeout = 600

  values = [
    yamlencode({
      global = {
        authentication = {
          provider = "basic"
        }
      }
      openmetadata = {
        config = {
          database = {
            host     = "openmetadata-dependencies-mysql"
            port     = 3306
            databaseName = "openmetadata_db"
            auth = {
              username = "openmetadata_user"
              password = {
                secretRef = "mysql-secrets"
                secretKey = "openmetadata-mysql-password"
              }
            }
          }
          elasticsearch = {
            host = "openmetadata-dependencies-elasticsearch"
            port = 9200
          }
          airflow = {
            enabled = true
            host    = "http://openmetadata-dependencies-airflow-web:8080"
          }
        }
      }
      service = {
        type = "ClusterIP"
        port = 8585
      }
    })
  ]

  depends_on = [helm_release.openmetadata_dependencies]
}

# Create MySQL secret for OpenMetadata
resource "kubernetes_secret" "mysql_secrets" {
  metadata {
    name      = "mysql-secrets"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  data = {
    "openmetadata-mysql-password" = base64encode("openmetadata_password")
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.main]
}

