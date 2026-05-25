variable "location_primary" { default = "centralindia" }
variable "location_secondary" { default = "eastus2" }

variable "hub_vnet_cidr" { default = "10.0.0.0/16" }
variable "spoke1_vnet_cidr" { default = "10.1.0.0/16" }
variable "spoke1_vmss_subnet" { default = "10.1.10.0/24" }
variable "spoke1_appgw_subnet" { default = "10.1.20.0/24" }
variable "spoke1_pe_subnet" { default = "10.1.30.0/24" }

variable "spoke2_vnet_cidr" { default = "10.2.0.0/16" }
variable "spoke2_vmss_subnet" { default = "10.2.10.0/24" }
variable "spoke2_appgw_subnet" { default = "10.2.20.0/24" }
variable "spoke2_pe_subnet" { default = "10.2.30.0/24" }
