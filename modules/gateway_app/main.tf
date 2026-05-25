variable "resource_group_name" {}
variable "location" {}
variable "appgw_name" {}
variable "subnet_id" {}

resource "azurerm_public_ip" "appgw_pip" {
  name                = "${var.appgw_name}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = var.appgw_name
}

resource "azurerm_web_application_firewall_policy" "waf" {
  name                = "${var.appgw_name}-wafpolicy"
  resource_group_name = var.resource_group_name
  location            = var.location

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
}

resource "azurerm_application_gateway" "appgw" {
  name                = var.appgw_name
  resource_group_name = var.resource_group_name
  location            = var.location
  firewall_policy_id  = azurerm_web_application_firewall_policy.waf.id

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }

  ssl_policy {
    policy_name = "AppGwSslPolicy20220101"
    policy_type = "Predefined"
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = var.subnet_id
  }

  frontend_port {
    name = "fe-port-80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "fe-ip-config"
    public_ip_address_id = azurerm_public_ip.appgw_pip.id
  }

  # --- Organic Ghee (flowforge.fun) ---
  backend_address_pool {
    name = "pool-ghee"
  }

  backend_http_settings {
    name                  = "http-settings-ghee"
    cookie_based_affinity = "Disabled"
    path                  = "/"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "probe-ghee"
  }

  http_listener {
    name                           = "listener-ghee"
    frontend_ip_configuration_name = "fe-ip-config"
    frontend_port_name             = "fe-port-80"
    protocol                       = "Http"
    host_names                     = ["flowforge.fun", "organic-ghee-tm.trafficmanager.net"]
  }

  request_routing_rule {
    name                       = "rule-ghee"
    rule_type                  = "Basic"
    http_listener_name         = "listener-ghee"
    backend_address_pool_name  = "pool-ghee"
    backend_http_settings_name = "http-settings-ghee"
    priority                   = 10
  }

  probe {
    name                                      = "probe-ghee"
    protocol                                  = "Http"
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = false
    host                                      = "flowforge.fun"
  }

  # --- Fitness Tracker (fitness.flowforge.fun) ---
  backend_address_pool {
    name = "pool-fitness"
  }

  backend_http_settings {
    name                  = "http-settings-fitness"
    cookie_based_affinity = "Disabled"
    path                  = "/"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "probe-fitness"
  }

  http_listener {
    name                           = "listener-fitness"
    frontend_ip_configuration_name = "fe-ip-config"
    frontend_port_name             = "fe-port-80"
    protocol                       = "Http"
    host_names                     = ["fitness.flowforge.fun", "fitness-tracker-tm.trafficmanager.net"]
  }

  request_routing_rule {
    name                       = "rule-fitness"
    rule_type                  = "Basic"
    http_listener_name         = "listener-fitness"
    backend_address_pool_name  = "pool-fitness"
    backend_http_settings_name = "http-settings-fitness"
    priority                   = 20
  }

  probe {
    name                                      = "probe-fitness"
    protocol                                  = "Http"
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = false
    host                                      = "fitness.flowforge.fun"
  }
}

output "public_ip_id" { value = azurerm_public_ip.appgw_pip.id }
output "backend_address_pool_id_ghee" {
  value = tolist(azurerm_application_gateway.appgw.backend_address_pool)[0].id
}
output "backend_address_pool_id_fitness" {
  value = tolist(azurerm_application_gateway.appgw.backend_address_pool)[1].id
}
