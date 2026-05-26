
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}


resource "azurerm_resource_group" "rg_hub" {
  name     = "rg-hub-centralindia"
  location = var.location_primary
}

resource "azurerm_resource_group" "rg_spoke1" {
  name     = "rg-spoke1-centralindia"
  location = var.location_primary
}

resource "azurerm_resource_group" "rg_spoke2" {
  name     = "rg-spoke2-eastus2"
  location = var.location_secondary
}

module "network_hub" {
  source              = "./modules/network_hub"
  resource_group_name = azurerm_resource_group.rg_hub.name
  location            = azurerm_resource_group.rg_hub.location
  vnet_cidr           = var.hub_vnet_cidr
}

module "network_spoke1" {
  source               = "./modules/network_spoke"
  resource_group_name  = azurerm_resource_group.rg_spoke1.name
  location             = azurerm_resource_group.rg_spoke1.location
  vnet_name            = "vnet-spoke1"
  vnet_cidr            = var.spoke1_vnet_cidr
  hub_vnet_name        = module.network_hub.hub_vnet_name
  hub_vnet_id          = module.network_hub.hub_vnet_id
  hub_rg_name          = azurerm_resource_group.rg_hub.name
  firewall_private_ip  = module.network_hub.firewall_private_ip
  vmss_subnet_cidr     = var.spoke1_vmss_subnet
  appgw_subnet_cidr    = var.spoke1_appgw_subnet
  pe_subnet_cidr       = var.spoke1_pe_subnet
}

module "network_spoke2" {
  source               = "./modules/network_spoke"
  resource_group_name  = azurerm_resource_group.rg_spoke2.name
  location             = azurerm_resource_group.rg_spoke2.location
  vnet_name            = "vnet-spoke2"
  vnet_cidr            = var.spoke2_vnet_cidr
  hub_vnet_name        = module.network_hub.hub_vnet_name
  hub_vnet_id          = module.network_hub.hub_vnet_id
  hub_rg_name          = azurerm_resource_group.rg_hub.name
  firewall_private_ip  = module.network_hub.firewall_private_ip
  vmss_subnet_cidr     = var.spoke2_vmss_subnet
  appgw_subnet_cidr    = var.spoke2_appgw_subnet
  pe_subnet_cidr       = var.spoke2_pe_subnet
}

module "security_rules" {
  source              = "./modules/security_rules"
  firewall_name       = module.network_hub.firewall_name
  resource_group_name = azurerm_resource_group.rg_hub.name
}

module "database" {
  source              = "./modules/database"
  resource_group_name = azurerm_resource_group.rg_hub.name
  location_primary    = var.location_primary
  location_secondary  = var.location_secondary
  spoke1_vnet_id      = module.network_spoke1.vnet_id
  spoke2_vnet_id      = module.network_spoke2.vnet_id
  spoke1_pe_subnet_id = module.network_spoke1.pe_subnet_id
  spoke2_pe_subnet_id = module.network_spoke2.pe_subnet_id
}

module "compute_vmss_spoke1_ghee" {
  source              = "./modules/compute_vmss"
  resource_group_name = azurerm_resource_group.rg_spoke1.name
  location            = azurerm_resource_group.rg_spoke1.location
  vmss_name           = "vmss-spoke1-ghee"
  subnet_id           = module.network_spoke1.vmss_subnet_id
  appgw_backend_id    = module.gateway_app_spoke1.backend_address_pool_id_ghee
  bootstrap_script    = base64encode(templatefile("${path.module}/scripts/bootstrap_ghee.sh.tftpl", { MONGODB_URI = replace(module.database.connection_string, "/?ssl=true", "/restaurant?ssl=true") }))
}

module "compute_vmss_spoke1_fitness" {
  source              = "./modules/compute_vmss"
  resource_group_name = azurerm_resource_group.rg_spoke1.name
  location            = azurerm_resource_group.rg_spoke1.location
  vmss_name           = "vmss-spoke1-fitness"
  subnet_id           = module.network_spoke1.vmss_subnet_id
  appgw_backend_id    = module.gateway_app_spoke1.backend_address_pool_id_fitness
  bootstrap_script    = base64encode(templatefile("${path.module}/scripts/bootstrap_fitness.sh.tftpl", { MONGODB_URI = replace(module.database.connection_string, "/?ssl=true", "/fitness-tracker?ssl=true") }))
}

module "compute_vmss_spoke2_ghee" {
  source              = "./modules/compute_vmss"
  resource_group_name = azurerm_resource_group.rg_spoke2.name
  location            = azurerm_resource_group.rg_spoke2.location
  vmss_name           = "vmss-spoke2-ghee"
  subnet_id           = module.network_spoke2.vmss_subnet_id
  appgw_backend_id    = module.gateway_app_spoke2.backend_address_pool_id_ghee
  bootstrap_script    = base64encode(templatefile("${path.module}/scripts/bootstrap_ghee.sh.tftpl", { MONGODB_URI = replace(module.database.connection_string, "/?ssl=true", "/restaurant?ssl=true") }))
}

module "compute_vmss_spoke2_fitness" {
  source              = "./modules/compute_vmss"
  resource_group_name = azurerm_resource_group.rg_spoke2.name
  location            = azurerm_resource_group.rg_spoke2.location
  vmss_name           = "vmss-spoke2-fitness"
  subnet_id           = module.network_spoke2.vmss_subnet_id
  appgw_backend_id    = module.gateway_app_spoke2.backend_address_pool_id_fitness
  bootstrap_script    = base64encode(templatefile("${path.module}/scripts/bootstrap_fitness.sh.tftpl", { MONGODB_URI = replace(module.database.connection_string, "/?ssl=true", "/fitness-tracker?ssl=true") }))
}

module "gateway_app_spoke1" {
  source              = "./modules/gateway_app"
  resource_group_name = azurerm_resource_group.rg_spoke1.name
  location            = azurerm_resource_group.rg_spoke1.location
  appgw_name          = "appgw-spoke1"
  subnet_id           = module.network_spoke1.appgw_subnet_id
}

module "gateway_app_spoke2" {
  source              = "./modules/gateway_app"
  resource_group_name = azurerm_resource_group.rg_spoke2.name
  location            = azurerm_resource_group.rg_spoke2.location
  appgw_name          = "appgw-spoke2"
  subnet_id           = module.network_spoke2.appgw_subnet_id
}

resource "azurerm_traffic_manager_profile" "tm_ghee" {
  name                   = "tm-organic-ghee"
  resource_group_name    = azurerm_resource_group.rg_hub.name
  traffic_routing_method = "Priority"
  dns_config {
    relative_name = "organic-ghee-tm"
    ttl           = 100
  }
  monitor_config {
    protocol                     = "HTTP"
    port                         = 80
    path                         = "/"
    interval_in_seconds          = 30
    timeout_in_seconds           = 10
    tolerated_number_of_failures = 3
  }
}

resource "azurerm_traffic_manager_azure_endpoint" "tm_ghee_ep1" {
  name               = "ep-ghee-spoke1"
  profile_id         = azurerm_traffic_manager_profile.tm_ghee.id
  weight             = 100
  target_resource_id = module.gateway_app_spoke1.public_ip_id
}

resource "azurerm_traffic_manager_azure_endpoint" "tm_ghee_ep2" {
  name               = "ep-ghee-spoke2"
  profile_id         = azurerm_traffic_manager_profile.tm_ghee.id
  weight             = 100
  target_resource_id = module.gateway_app_spoke2.public_ip_id
}

resource "azurerm_traffic_manager_profile" "tm_fitness" {
  name                   = "tm-fitness-tracker"
  resource_group_name    = azurerm_resource_group.rg_hub.name
  traffic_routing_method = "Priority"
  dns_config {
    relative_name = "fitness-tracker-tm"
    ttl           = 100
  }
  monitor_config {
    protocol                     = "HTTP"
    port                         = 80
    path                         = "/"
    interval_in_seconds          = 30
    timeout_in_seconds           = 10
    tolerated_number_of_failures = 3
  }
}

resource "azurerm_traffic_manager_azure_endpoint" "tm_fitness_ep1" {
  name               = "ep-fitness-spoke1"
  profile_id         = azurerm_traffic_manager_profile.tm_fitness.id
  weight             = 100
  target_resource_id = module.gateway_app_spoke1.public_ip_id
}

resource "azurerm_traffic_manager_azure_endpoint" "tm_fitness_ep2" {
  name               = "ep-fitness-spoke2"
  profile_id         = azurerm_traffic_manager_profile.tm_fitness.id
  weight             = 100
  target_resource_id = module.gateway_app_spoke2.public_ip_id
}
