output "organic_ghee_traffic_manager_url" {
  description = "The Traffic Manager URL for the Organic Ghee app. Point your CNAME record here."
  value       = azurerm_traffic_manager_profile.tm_ghee.fqdn
}

output "fitness_tracker_traffic_manager_url" {
  description = "The Traffic Manager URL for the Fitness Tracker app. Point your CNAME record here."
  value       = azurerm_traffic_manager_profile.tm_fitness.fqdn
}

output "dns_instructions" {
  description = "Instructions for configuring your DNS provider."
  value = <<EOT
To configure your custom domains, go to your DNS provider (e.g., GoDaddy, Cloudflare) and add the following CNAME records:

1. For Organic Ghee:
   Type: CNAME
   Name: @ (or www) -> for flowforge.fun
   Value: ${azurerm_traffic_manager_profile.tm_ghee.fqdn}

2. For Fitness Tracker:
   Type: CNAME
   Name: fitness -> for fitness.flowforge.fun
   Value: ${azurerm_traffic_manager_profile.tm_fitness.fqdn}
EOT
}
