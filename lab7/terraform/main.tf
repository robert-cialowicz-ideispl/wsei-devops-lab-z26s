terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "vm_size" {
  type    = string
  default = "Standard_D2als_v6"
}

resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_kubernetes_cluster" "lab" {
  name                              = var.cluster_name
  location                          = azurerm_resource_group.lab.location
  resource_group_name               = azurerm_resource_group.lab.name
  dns_prefix                        = var.cluster_name
  sku_tier                          = "Free"
  role_based_access_control_enabled = true
  local_account_disabled            = true

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
  }

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name            = "system"
    type            = "VirtualMachineScaleSets"
    os_sku          = "Ubuntu"
    node_count      = 2
    vm_size         = var.vm_size
    max_pods        = 30
    os_disk_size_gb = 64
    os_disk_type    = "Managed"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }
}
