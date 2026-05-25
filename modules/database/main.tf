variable "resource_group_name" {}
variable "location_primary" {}
variable "location_secondary" {}
variable "spoke1_vnet_id" {}
variable "spoke2_vnet_id" {}
variable "spoke1_pe_subnet_id" {}
variable "spoke2_pe_subnet_id" {}

resource "azurerm_cosmosdb_account" "db" {
  name                = "cosmos-mongodb-global"
  location            = var.location_primary
  resource_group_name = var.resource_group_name
  offer_type          = "Standard"
  kind                = "MongoDB"
  mongo_server_version = "4.2"

  capabilities {
    name = "EnableMongo"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location_primary
    failover_priority = 0
  }

  geo_location {
    location          = var.location_secondary
    failover_priority = 1
  }
}

resource "azurerm_private_dns_zone" "dns" {
  name                = "privatelink.mongo.cosmos.azure.com"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "link1" {
  name                  = "link-spoke1"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.dns.name
  virtual_network_id    = var.spoke1_vnet_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "link2" {
  name                  = "link-spoke2"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.dns.name
  virtual_network_id    = var.spoke2_vnet_id
}

resource "azurerm_private_endpoint" "pe1" {
  name                = "pe-cosmos-spoke1"
  location            = var.location_primary
  resource_group_name = var.resource_group_name
  subnet_id           = var.spoke1_pe_subnet_id

  private_service_connection {
    name                           = "cosmos-privatelink"
    private_connection_resource_id = azurerm_cosmosdb_account.db.id
    subresource_names              = ["MongoDB"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.dns.id]
  }
}

resource "azurerm_private_endpoint" "pe2" {
  name                = "pe-cosmos-spoke2"
  location            = var.location_secondary
  resource_group_name = var.resource_group_name
  subnet_id           = var.spoke2_pe_subnet_id

  private_service_connection {
    name                           = "cosmos-privatelink"
    private_connection_resource_id = azurerm_cosmosdb_account.db.id
    subresource_names              = ["MongoDB"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.dns.id]
  }
}

output "connection_string" {
  value = azurerm_cosmosdb_account.db.primary_mongodb_connection_string
  sensitive = true
}
