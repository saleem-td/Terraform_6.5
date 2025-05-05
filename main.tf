terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.23.0" # Replace with the version you are using
    }
  }
}


provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}


module "compute" {
  source                  = "./modules/compute"
  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  vm_name                 = var.vm_name
  vm_size                 = var.vm_size
  subnet_id               = module.networking.subnet_id
  public_ip_id            = module.networking.public_ip_id 
  nic_name                = var.nic_name
  nsg_id_vmss             = module.networking.nsg_id_vmss
  nsg_id_chroma           = module.networking.nsg_id_chroma
  nsg_name_chroma         = var.nsg_name_chroma
  nsg_name_vmss           = var.nsg_name_vmss
  github_token            = var.github_token
  repo_url                = var.repo_url
  openai_api_key          = var.openai_api_key
  db_name                 = var.db_name
  db_user                 = var.db_user
  db_password             = var.db_password
  db_host                 = module.storage.fqdn
  db_port                 = var.db_port
  azure_storage_container = var.azure_storage_container
  chromadb_host           = var.chromadb_host 
  chromadb_port           = var.chromadb_port  
  azure_storage_sas_url   = module.storage.sas_url  
  directory               = var.directory
  ssh_dir                 = var.ssh_dir
  host_name               = var.host_name 
  vmss_name               = var.vmss_name
  application_gateway_backend_pool = module.networking.application_gateway_backend_pool
  key_vault_name                   = var.key_vault_name 
}



module "networking" {
  source                  = "./modules/networking"
  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  vnet_name               = var.vnet_name 
  subnet_name             = var.subnet_name  
  public_ip_name          = var.public_ip_name 
  nsg_name_chroma         = var.nsg_name_chroma
  nsg_name_vmss           = var.nsg_name_vmss
  public_ip_name_appgw    = var.public_ip_name_appgw
  subnet_name_appgw       = var.subnet_name_appgw 
  # instances               = module.compute.instances
  # vmss_private_ip         = module.compute.vmss_private_ip
}

module "storage" {
  source                        = "./modules/storage"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  db_name                       = var.db_name
  db_user                       = var.db_user
  db_password                   = var.db_password 
  azure_storage_container       = var.azure_storage_container 
  azure_storage_account_name    = var.azure_storage_account_name  
}