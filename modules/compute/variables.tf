variable "resource_group_name" {} 
variable "location" {} 
variable "vm_name" {}
variable "vm_size" {type = string}
variable "subnet_id" {} 
variable "public_ip_id" {} 
variable "nic_name" {}
variable "azure_storage_sas_url" {}
variable "azure_storage_container" {}
variable "directory"{}
variable "ssh_dir" {}
variable "github_token" {}
variable "repo_url" {}
variable "openai_api_key" {}
variable "db_name" {} 
variable "db_user" {}                   
variable "db_password" {} 
variable "db_host" {}               
variable "db_port" {}   
variable "chromadb_host" {}  
variable "chromadb_port" {}       
variable "host_name" {}          
variable "vmss_name" {} 
variable "nsg_id_chroma"{}
variable "nsg_id_vmss"{}
variable "nsg_name_chroma" {}
variable "nsg_name_vmss" {}
variable "application_gateway_backend_pool" {}
variable "key_vault_name" {}

