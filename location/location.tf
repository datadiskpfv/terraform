# tfvars file variables
variable "web_server_location" {}
variable "web_server_rg" {}
variable "resource_prefix" {}
variable "web_server_address_space" {}
variable "web_server_name" {}
variable "environment" {}
variable "web_server_count" {}
variable "web_server_subnets" { type = "list" }
variable "terraform_script_version" {}
variable "domain_name_label" {}

# Local variables (called Locals)
locals {
  web_server_name     = "${var.environment == "production" ? "${var.web_server_name}-prd" : "${var.web_server_name}-dev" }"
  build_environment   = "${var.environment == "production" ? "production" : "development"}"
}

# Resource Group - Web Server
resource "azurerm_resource_group" "web_server_rg" {
    name        = "${var.web_server_rg}"
    location    = "${var.web_server_location}"

    tags {
      environment   = "${local.build_environment}"
      build-version = "${var.terraform_script_version}"
    }

    # Prevent this resource being destroyed
//    lifecycle {
//      prevent_destroy = true
//    }
}

# Resource Group - Network Watcher
resource "azurerm_resource_group" "network_watcher_rg" {
    name                = "NetworkWatcherRG"
    location            = "${var.web_server_location}"
}

# Virtual Network - Web Network
resource "azurerm_virtual_network" "web_server_vnet" {
    address_space       = ["${var.web_server_address_space}"]
    location            = "${var.web_server_location}"
    name                = "${var.resource_prefix}-vnet"
    resource_group_name = "${azurerm_resource_group.web_server_rg.name}"
}

# Virtual Network Subnet - Web Network
resource "azurerm_subnet" "web_server_subnet" {
    address_prefix            = "${var.web_server_subnets[count.index]}"
    name                      = "${var.resource_prefix}-${substr(var.web_server_subnets[count.index], 0, length(var.web_server_subnets[count.index]) - 3)}-subnet"
    resource_group_name       = "${azurerm_resource_group.web_server_rg.name}"
    virtual_network_name      = "${azurerm_virtual_network.web_server_vnet.name}"
    network_security_group_id = "${count.index == 0 ? "${azurerm_network_security_group.web_server_nsg.id}" : "" }"
    count                     = "${length(var.web_server_subnets)}"
}

//# Virtual Network Interface - Web server
//resource "azurerm_network_interface" "web_server_nic" {
//    location            = "${var.web_server_location}"
//    name                = "${var.web_server_name}-${format("%02d", count.index)}-nic"
//    resource_group_name = "${azurerm_resource_group.web_server_rg.name}"
//    count               = "${var.web_server_count}"
//
//    "ip_configuration" {
//        name                            = "${var.web_server_name}-${format("%02d", count.index)}-ip"
//        private_ip_address_allocation   = "dynamic"
//        subnet_id                       = "${azurerm_subnet.web_server_subnet.*.id[count.index]}"
//        public_ip_address_id            = "${azurerm_public_ip.web_server_public_ip.*.id[count.index]}"
//    }
//}

# Public IP address - bind to above IP
resource "azurerm_public_ip" "web_server_lb_public_ip" {
    location                        = "${var.web_server_location}"
    name                            = "${var.resource_prefix}-public-ip"
    resource_group_name             = "${azurerm_resource_group.web_server_rg.name}"
    # use a conditional to determine if to use static or dynamic
    public_ip_address_allocation    = "${var.environment == "production" ? "static" : "dynamic"}"
    domain_name_label               = "${var.domain_name_label}"
}

# Network Security Group - Web Network
resource "azurerm_network_security_group" "web_server_nsg" {
  location            = "${var.web_server_location}"
  name                = "${var.resource_prefix}-nsg"
  resource_group_name = "${azurerm_resource_group.web_server_rg.name}"
}

# Network Security Group Rule RDP
resource "azurerm_network_security_rule" "web_server_nsg_rule_http" {
  access                      = "Allow"
  direction                   = "Inbound"
  name                        = "HTTP Inbound"
  network_security_group_name = "${azurerm_network_security_group.web_server_nsg.name}"
  priority                    = 100
  protocol                    = "TCP"
  resource_group_name         = "${azurerm_resource_group.web_server_rg.name}"
  source_address_prefix       = "*"
  source_port_range           = "*"
  destination_address_prefix  = "*"
  destination_port_range      = "80"
}

# Virtual Machine Scale Set - Web Servers
resource "azurerm_virtual_machine_scale_set" "web_server" {
  location                = "${var.web_server_location}"
  name                    = "${var.resource_prefix}-scale-set"
  resource_group_name     = "${azurerm_resource_group.web_server_rg.name}"
  upgrade_policy_mode     = "manual"

  sku {
    name          = "Standard_B1s"
    tier          = "Standard"
    capacity      = "${var.web_server_count}"
  }

  "storage_profile_image_reference" {
    publisher     = "MicrosoftWindowsServer"
    offer         = "WindowsServer"
    sku           = "2016-Datacenter-Server-Core-smalldisk"
    version       = "latest"
  }

  "storage_profile_os_disk" {
    create_option       = "FromImage"
    name                = ""
    caching             = "ReadWrite"
    managed_disk_type   = "Standard_LRS"
  }

  "os_profile" {
    computer_name_prefix = "${local.web_server_name}"
    admin_username = "webserver"
    admin_password = "Passw0rd1234"
  }

  "os_profile_windows_config" {
    provision_vm_agent = true
  }

  "network_profile" {
    name = "web_server_network_profile"
    primary = true

    "ip_configuration" {
      name = "${local.web_server_name}"
      primary = true
      subnet_id = "${azurerm_subnet.web_server_subnet.*.id[0]}"
      load_balancer_backend_address_pool_ids = ["${azurerm_lb_backend_address_pool.web_server_lb_backend_pool.id}"]
    }
  }

  # Azure VM extension - Used to scripts on vm to install software, configure vm, etc
  extension {
    name                  = "${local.web_server_name}-extension"
    publisher             = "Microsoft.Compute"
    type                  = "CustomScriptExtension"
    type_handler_version  = "1.9"

    settings              = <<SETTINGS
    {
      "fileUris": ["https://raw.githubusercontent.com/eltimmo/learning/master/azureInstallWebServer.ps1"],
      "commandToExecute": "start powershell -ExecutionPolicy Unrestricted -file azureInstallWebServer.ps1"
    }
    SETTINGS
  }
}

# Load Balancer - Scale Set Web Servers
resource "azurerm_lb" "web_server_lb" {
  location                = "${var.web_server_location}"
  name                    = "${var.resource_prefix}-lb"
  resource_group_name     = "${azurerm_resource_group.web_server_rg.name}"

  frontend_ip_configuration {
    name                  = "${var.resource_prefix}-lb-frontend-ip"
    public_ip_address_id  = "${azurerm_public_ip.web_server_lb_public_ip.id}"
  }
}

resource "azurerm_lb_backend_address_pool" "web_server_lb_backend_pool" {
  loadbalancer_id         = "${azurerm_lb.web_server_lb.id}"
  name                    = "${var.resource_prefix}-lb-backend-pool"
  resource_group_name     = "${azurerm_resource_group.web_server_rg.name}"
}

resource "azurerm_lb_probe" "web_server_lb_http_probe" {
  loadbalancer_id     = "${azurerm_lb.web_server_lb.id}"
  name                = "${var.resource_prefix}-lb-http-probe"
  resource_group_name = "${azurerm_resource_group.web_server_rg.name}"
  protocol            = "tcp"
  port                = "80"
}

resource "azurerm_lb_rule" "web_server_lb_http_rule" {
  name                            = "${var.resource_prefix}-lb-http-rule"
  resource_group_name             = "${azurerm_resource_group.web_server_rg.name}"

  loadbalancer_id                 = "${azurerm_lb.web_server_lb.id}"
  backend_address_pool_id         = "${azurerm_lb_backend_address_pool.web_server_lb_backend_pool.id}"
  backend_port                    = "80"
  frontend_ip_configuration_name  = "${var.resource_prefix}-lb-frontend-ip"
  frontend_port                   = "80"
  protocol                        = "tcp"
  probe_id                        = "${azurerm_lb_probe.web_server_lb_http_probe.id}"
}

//# Availability Set - Web Server
//resource "azurerm_availability_set" "web_server_availability_set" {
//  location                    = "${var.web_server_location}"
//  name                        = "${var.web_server_name}-availability-set"
//  resource_group_name         = "${azurerm_resource_group.web_server_rg.name}"
//  managed                     = true
//  platform_fault_domain_count = 2
//}
