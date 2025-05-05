output "sas_url" {
  description = "SAS URL with full permissions over HTTP & HTTPS"
  value       = "${azurerm_storage_account.storage.primary_blob_endpoint}${data.azurerm_storage_account_sas.storage.sas}"
}

output "fqdn" {
  value = azurerm_postgresql_flexible_server.storage.fqdn
}
