# resource "azurerm_postgresql_flexible_server" "storage" {
#   name                          ="sda-main-psqlflexibleserver"
#   resource_group_name           =var.resource_group_name
#   location                      =var.location
#   version                       ="16"
#   administrator_login           =var.
#   administrator_password        = "K7254Talal@"
#   zone                          = "1"
#   storage_mb   = 32768
#   storage_tier = "P4"
#   sku_name   = "B_Standard_B1ms"
#   geo_redundant_backup_enabled = false
# }

resource "azurerm_postgresql_flexible_server" "storage" {
  name                          = "sdapsqlflexibleserver"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = "16"
  public_network_access_enabled = true
  administrator_login           = var.db_user
  administrator_password        = var.db_password
  zone                          = "1"

  storage_mb   = 32768
  storage_tier = "P4"
  sku_name   = "B_Standard_B1ms"
  geo_redundant_backup_enabled = false
}


resource "azurerm_postgresql_flexible_server_firewall_rule" "storage" {
  name      = "office"
  server_id = azurerm_postgresql_flexible_server.storage.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

resource "azurerm_postgresql_flexible_server_database" "storage" {
  name       = var.db_name
  server_id  = azurerm_postgresql_flexible_server.storage.id
  collation  = "en_US.utf8"
  charset    = "UTF8"
  
  # lifecycle {
  #   prevent_destroy = true
  # }
}

# resource "azurerm_postgresql_database" "storage" {
#   name                = "appdb"
#   resource_group_name = var.resource_group_name
#   server_name         = azurerm_postgresql_server.storage.name
#   charset             = "UTF8"
#   collation           = "English_United States.1252"
# }

resource "null_resource" "postgresql_setup" {
  triggers = {
    postgres_server_name = azurerm_postgresql_flexible_server.storage.name
  }
  provisioner "local-exec" {
    command = <<EOT
      PGPASSWORD='${var.db_password}' psql -h ${azurerm_postgresql_flexible_server.storage.fqdn} -U ${var.db_user} -d ${var.db_name} -c "
      CREATE USER appuser WITH ENCRYPTED PASSWORD '${var.db_password}';
      GRANT ALL PRIVILEGES ON DATABASE ${azurerm_postgresql_flexible_server_database.storage.name} TO appuser;
      GRANT ALL PRIVILEGES ON SCHEMA public TO appuser;
      CREATE TABLE IF NOT EXISTS advanced_chats (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        file_path TEXT NOT NULL, 
        last_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        pdf_path TEXT,
        pdf_name TEXT,
        pdf_uuid TEXT
      );
      "
    EOT
  }
}

resource "azurerm_storage_account" "storage" {
  name                     = var.azure_storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "storage" {
  name                  = var.azure_storage_container
  storage_account_id    = azurerm_storage_account.storage.id
  container_access_type = "private"
}


data "azurerm_storage_account_sas" "storage" {
  connection_string = azurerm_storage_account.storage.primary_connection_string

  # allow both http and https
  https_only = false

  # start now, expire in 30 days
  start          = formatdate("YYYY-MM-DD'T'HH:mm:ss'Z'", timestamp())
  expiry         = timeadd(formatdate("YYYY-MM-DD'T'HH:mm:ss'Z'", timestamp()), "720h")
  signed_version = "2021-12-02"

  # enable every service
  services {
    blob  = true
    file  = true
    queue = true
    table = true
  }

  # enable every resource type
  resource_types {
    service   = true
    container = true
    object    = true
  }

  # grant every permission
  permissions {
    read    = true
    write   = true
    delete  = true
    list    = true
    add     = true
    create  = true
    update  = true
    process = true
    filter  = true
    tag     = true
  }

  # ensure container exists before generating SAS
  depends_on = [azurerm_storage_container.storage]
}
resource "time_static" "now" {}