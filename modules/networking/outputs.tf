output "subnet_id"         { value = azurerm_subnet.networking.id }
output "public_ip_id"      { value = azurerm_public_ip.networking.id }
output "public_ip_address" { value = azurerm_public_ip.networking.ip_address }
output "nsg_id_chroma"     { value = azurerm_network_security_group.chroma.id }
output "nsg_id_vmss"       { value = azurerm_network_security_group.vmss.id }
output "application_gateway_backend_pool" {value = one([for pool in azurerm_application_gateway.appgw.backend_address_pool : pool.id if pool.name == "vmss-backend-pool"])}
