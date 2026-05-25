variable "firewall_name" {}
variable "resource_group_name" {}

resource "azurerm_firewall_application_rule_collection" "app_rules" {
  name                = "app-rules-tf"
  azure_firewall_name = var.firewall_name
  resource_group_name = var.resource_group_name
  priority            = 100
  action              = "Allow"

  rule {
    name = "Allow-OS-Updates"
    source_addresses = ["10.0.0.0/16", "10.1.0.0/16", "10.2.0.0/16"]
    target_fqdns = ["*.ubuntu.com", "*.archive.ubuntu.com"]
    protocol {
      port = "80"
      type = "Http"
    }
    protocol {
      port = "443"
      type = "Https"
    }
  }

  rule {
    name = "Allow-Node-Deps"
    source_addresses = ["10.0.0.0/16", "10.1.0.0/16", "10.2.0.0/16"]
    target_fqdns = ["*.nodesource.com", "*.npmjs.com", "*.npmjs.org", "registry.npmjs.org"]
    protocol {
      port = "443"
      type = "Https"
    }
  }

  rule {
    name = "Allow-Git-Clone"
    source_addresses = ["10.0.0.0/16", "10.1.0.0/16", "10.2.0.0/16"]
    target_fqdns = ["github.com", "*.github.com", "*.githubusercontent.com"]
    protocol {
      port = "443"
      type = "Https"
    }
  }
}

resource "azurerm_firewall_network_rule_collection" "net_rules" {
  name                = "net-rules-tf"
  azure_firewall_name = var.firewall_name
  resource_group_name = var.resource_group_name
  priority            = 100
  action              = "Allow"

  rule {
    name = "Allow-CosmosDB"
    source_addresses = ["10.0.0.0/16", "10.1.0.0/16", "10.2.0.0/16"]
    destination_addresses = ["AzureCosmosDB"]
    destination_ports = ["443"]
    protocols = ["TCP"]
  }

  rule {
    name = "Allow-DNS"
    source_addresses = ["10.0.0.0/16", "10.1.0.0/16", "10.2.0.0/16"]
    destination_addresses = ["168.63.129.16"]
    destination_ports = ["53"]
    protocols = ["UDP"]
  }

  rule {
    name = "Allow-AppGW-to-VMSS"
    source_addresses = ["10.0.0.0/16", "10.1.0.0/16", "10.2.0.0/16"]
    destination_addresses = ["10.0.0.0/16", "10.1.0.0/16", "10.2.0.0/16"]
    destination_ports = ["80"]
    protocols = ["TCP"]
  }
}
