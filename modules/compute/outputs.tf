output "nic_id" { value = azurerm_network_interface.com.id }
output "vm_id" { value = azurerm_linux_virtual_machine.com.id }
#output "vmss_private_ip" {value = data.azurerm_linux_virtual_machine_scale_set.private_ip_address}
output "instances" { value = azurerm_linux_virtual_machine_scale_set.vmss.instances}
# output "vmss_private_ip" {value = azurerm_linux_virtual_machine_scale_set.vmss.instances[*].private_ip_address}




