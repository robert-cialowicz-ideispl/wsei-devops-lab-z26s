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
  validation {
    condition     = can(regex("^rg-lab6-[0-9]+-tf$", var.resource_group_name))
    error_message = "Use rg-lab6-<student-number>-tf."
  }
}

variable "location" {
  type = string
}

variable "vm_size" {
  type    = string
  default = "Standard_B2ats_v2"

  validation {
    condition     = contains(["Standard_B1s", "Standard_B2ats_v2"], var.vm_size)
    error_message = "Use Standard_B1s or Standard_B2ats_v2."
  }
}

variable "ssh_public_key_path" {
  type = string
}

resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "lab" {
  name                = "lab6-vnet"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = ["10.60.0.0/16"]
}

resource "azurerm_subnet" "app" {
  name                            = "app"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.lab.name
  address_prefixes                = ["10.60.1.0/24"]
  default_outbound_access_enabled = true
}

resource "azurerm_network_security_group" "lab" {
  name                = "lab6-nsg"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.lab.id
}

resource "azurerm_network_interface" "lab" {
  name                = "lab6-nic"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location

  ip_configuration {
    name                          = "app"
    subnet_id                     = azurerm_subnet_network_security_group_association.app.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "lab" {
  name                            = "lab6-vm"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  size                            = var.vm_size
  admin_username                  = "labuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.lab.id]

  admin_ssh_key {
    username   = "labuser"
    public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server-gen1"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "bootstrap" {
  name                 = "lab6-bootstrap"
  virtual_machine_id   = azurerm_linux_virtual_machine.lab.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"

  protected_settings = jsonencode({
    script = filebase64("${path.module}/bootstrap.sh")
  })
}
