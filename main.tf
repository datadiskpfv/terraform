# CommandLine Variables
variable "client_id" {}                 # TF_VAR_client_id
variable "client_secret" {}             # TF_VAR_client_secret
variable "tenant_id" {}                 # TF_VAR_tenant_id
variable "subscription_id" {}           # TF_VAR_subscription_id

# TF_LOG        - TRACE, DEBUG, INFO, WARN and ERROR
# TF_LOG_PATH

# tfvars file variables
variable "web_server_rg" {}
variable "resource_prefix" {}
variable "web_server_name" {}
variable "environment" {}
variable "web_server_count" {}
variable "terraform_script_version" {}
variable "domain_name_label" {}

# Local variables (called Locals)
locals {
  web_server_name     = "${var.environment == "production" ? "${var.web_server_name}-prd" : "${var.web_server_name}-dev" }"
  build_environment   = "${var.environment == "production" ? "production" : "development"}"
}

# Azure credentials
provider "azurerm" {
    version         = "1.16"

    # Use environment variables to get Azure credentials
    client_id       = "${var.client_id}"
    client_secret   = "${var.client_secret}"
    tenant_id       = "${var.tenant_id}"
    subscription_id = "${var.subscription_id}"
}

module "location_us2w" {
  source = "./location"

  # pass the variables to the module
  web_server_location         = "westus2"
  web_server_rg               = "${var.web_server_rg}-us2w"
  resource_prefix             = "${var.resource_prefix}-us2w"
  web_server_address_space    = "1.0.0.0/22"
  web_server_name             = "${var.web_server_name}"
  environment                 = "${var.environment}"
  web_server_count            = "${var.web_server_count}"
  web_server_subnets          = ["1.0.1.0/24", "1.0.2.0/24"]
  domain_name_label           = "${var.domain_name_label}"
  terraform_script_version    = "${var.terraform_script_version}"
}

module "location_eu1w" {
  source = "./location"

  # pass the variables to the module
  web_server_location         = "westeurope"
  web_server_rg               = "${var.web_server_rg}-eu1w"
  resource_prefix             = "${var.resource_prefix}-eu1w"
  web_server_address_space    = "2.0.0.0/22"
  web_server_name             = "${var.web_server_name}"
  environment                 = "${var.environment}"
  web_server_count            = "${var.web_server_count}"
  web_server_subnets          = ["2.0.1.0/24", "2.0.2.0/24"]
  domain_name_label           = "${var.domain_name_label}"
  terraform_script_version    = "${var.terraform_script_version}"
}

resource "azurerm_traffic_manager_profile" "traffic-manager"{
  name                      = "${var.resource_prefix}-traffic-manager"
  resource_group_name       = "${module.location_us2w.web_server_rg_name}"
  traffic_routing_method    = "Weighted"

  "dns_config" {
    relative_name = "${var.domain_name_label}"
    ttl = 100
  }

  "monitor_config" {
    port      = 80
    protocol  = "http"
    path      = "/"
  }
}

resource "azurerm_traffic_manager_endpoint" "traffic-manager-us2w" {
  name                = "${var.resource_prefix}-traffic-manager-us2w-endpoint"
  profile_name        = "${azurerm_traffic_manager_profile.traffic-manager.name}"
  resource_group_name = "${module.location_us2w.web_server_rg_name}"
  target_resource_id  = "${module.location_us2w.web_server_lb_public_ip_id}"
  type                = "azureEndpoints"
  weight              = 100
}

resource "azurerm_traffic_manager_endpoint" "traffic-manager-eu1w" {
  name                = "${var.resource_prefix}-traffic-manager-eu1w-endpoint"
  profile_name        = "${azurerm_traffic_manager_profile.traffic-manager.name}"
  resource_group_name = "${module.location_us2w.web_server_rg_name}"
  target_resource_id  = "${module.location_eu1w.web_server_lb_public_ip_id}"
  type                = "azureEndpoints"
  weight              = 100
}
