variable "resource_group_name" {}
variable "location" {}
variable "vnet_name" {}
variable "vnet_cidr" {}
variable "hub_vnet_id" {}
variable "hub_vnet_name" {}
variable "hub_rg_name" {}
variable "firewall_private_ip" {}
variable "vmss_subnet_cidr" {}
variable "appgw_subnet_cidr" {}
variable "pe_subnet_cidr" {}

resource "azurerm_virtual_network" "spoke" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_cidr]
}

resource "azurerm_subnet" "vmss" {
  name                 = "VMSS-APP-SUBNET"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.vmss_subnet_cidr]
}

resource "azurerm_subnet" "appgw" {
  name                 = "AppGatewaySubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.appgw_subnet_cidr]
}

resource "azurerm_subnet" "pe" {
  name                 = "PrivateEndpointSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.pe_subnet_cidr]
}

# VMSS gets 0.0.0.0/0 to Firewall
resource "azurerm_route_table" "rt_vmss" {
  name                          = "rt-vmss-${var.vnet_name}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = true

  route {
    name                   = "To-Hub-Firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }

  route {
    name                   = "return-to-appgw-via-fw"
    address_prefix         = var.appgw_subnet_cidr
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }
}

resource "azurerm_subnet_route_table_association" "rt_vmss_assoc" {
  subnet_id      = azurerm_subnet.vmss.id
  route_table_id = azurerm_route_table.rt_vmss.id
}

# AppGW gets route to VMSS via Firewall
resource "azurerm_route_table" "rt_appgw" {
  name                          = "rt-appgw-${var.vnet_name}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = true

  route {
    name                   = "route-to-vmss-via-fw"
    address_prefix         = var.vmss_subnet_cidr
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }
}

resource "azurerm_subnet_route_table_association" "rt_appgw_assoc" {
  subnet_id      = azurerm_subnet.appgw.id
  route_table_id = azurerm_route_table.rt_appgw.id
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-${var.vnet_name}-to-hub"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = var.hub_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-hub-to-${var.vnet_name}"
  resource_group_name       = var.hub_rg_name
  virtual_network_name      = var.hub_vnet_name
  remote_virtual_network_id = azurerm_virtual_network.spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}


# App Gateway NSG
resource "azurerm_network_security_group" "nsg_appgw" {
  name                = "nsg-appgw-${var.vnet_name}"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "Allow-GatewayManager"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg_appgw_assoc" {
  subnet_id                 = azurerm_subnet.appgw.id
  network_security_group_id = azurerm_network_security_group.nsg_appgw.id
}

# VMSS NSG
resource "azurerm_network_security_group" "nsg_vmss" {
  name                = "nsg-vmss-${var.vnet_name}"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "Allow-AppGW"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = var.appgw_subnet_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg_vmss_assoc" {
  subnet_id                 = azurerm_subnet.vmss.id
  network_security_group_id = azurerm_network_security_group.nsg_vmss.id
}
output "vnet_id" { value = azurerm_virtual_network.spoke.id }
output "vmss_subnet_id" { value = azurerm_subnet.vmss.id }
output "appgw_subnet_id" { value = azurerm_subnet.appgw.id }
output "pe_subnet_id" { value = azurerm_subnet.pe.id }
