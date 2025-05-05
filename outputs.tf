output "public_ip_address" { value = module.networking.public_ip_address }
output "vm_id" { value = module.compute.vm_id }
# output "vmss_private_ip" {value = module.compute.vmss_private_ip}
