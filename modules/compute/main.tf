resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = "${var.vmss_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.vm_size
  instances           = 2                           

  admin_username = "${var.host_name}"
  
  disable_password_authentication = true

  admin_ssh_key {
    username   = "${var.host_name}"
    public_key = file("${var.ssh_dir}")
  }

  source_image_reference { 
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"  # Standard HDD :contentReference[oaicite:4]{index=4}
    disk_size_gb         = 30              # 30 GB OS disk
  }

  network_interface {
    name                      = "nic"
    primary                   = true
    network_security_group_id = var.nsg_id_vmss

    ip_configuration {
      name      = "internal"
      subnet_id = var.subnet_id
      primary   = true
      application_gateway_backend_address_pool_ids = [var.application_gateway_backend_pool]
    }
  }

identity {
    type = "SystemAssigned"
  }



  upgrade_mode = "Automatic"
    custom_data = base64encode(<<-EOT
#cloud-config
write_files:
  - path: /etc/systemd/system/backend.service
    permissions: '0644'
    owner: root:root
    content: |
      [Unit]
      Description=backend
      After=network.target

      [Service]
      Type=simple
      User=${var.host_name}
      WorkingDirectory=/home/${var.host_name}/${var.directory}
      ExecStart=/home/${var.host_name}/${var.directory}/venv/bin/uvicorn backend:app --reload --host 0.0.0.0 --port 5000
      StandardOutput=append:/home/${var.host_name}/${var.directory}/logs/backend.out.log
      StandardError=append:/home/${var.host_name}/${var.directory}/logs/backend.err.log
      Restart=always

      [Install]
      WantedBy=multi-user.target

  - path: /etc/systemd/system/frontend.service
    permissions: '0644'
    owner: root:root
    content: |
      [Unit]
      Description=Streamlit
      After=network.target

      [Service]
      Type=simple
      User=${var.host_name}
      WorkingDirectory=/home/${var.host_name}/${var.directory}
      ExecStart=/home/${var.host_name}/${var.directory}/venv/bin/streamlit run chatbot.py
      StandardOutput=append:/home/${var.host_name}/${var.directory}/logs/frontend.out.log
      StandardError=append:/home/${var.host_name}/${var.directory}/logs/frontend.err.log
      Restart=always

      [Install]
      WantedBy=multi-user.target
  
runcmd:
  - sudo apt update && sudo apt install python3-pip python3-venv wget gnupg2 lsb-release git -y
  - cd /home/${var.host_name}
  - mkdir -p logs
  - export github_token=${var.github_token}
  - export repo_url=${var.repo_url}
  - git clone -b main "https://${var.github_token}@${var.repo_url}"
  - cd ${var.directory}
  - echo "KEY_VAULT_NAME=${var.key_vault_name}" >> .env
  - python3 -m venv /home/${var.host_name}/${var.directory}/venv  
  - source /home/${var.host_name}/${var.directory}/venv/bin/activate 
  - /home/${var.host_name}/${var.directory}/venv/bin/pip install -r /home/${var.host_name}/${var.directory}/requirements.txt 
  - sudo systemctl daemon-reload
  - sudo systemctl enable backend frontend
  - mkdir -p /home/${var.host_name}/${var.directory}/logs
  - chown ${var.host_name}:${var.host_name} -R /home/${var.host_name}/${var.directory}
  - cd /home/${var.host_name}
  - sudo apt update
  - sudo systemctl start backend frontend
  - sleep 50
  - sudo systemctl restart frontend backend
  - cd /home/${var.host_name}/${var.directory}
  - |
    tee update_app.sh > /dev/null <<'EOF'
    #!/bin/bash
    set -e

    date
    echo "Updating Python application on VM..."

    APP_DIR="/home/${var.host_name}/${var.directory}"
    GIT_REPO="https://${var.repo_url}"
    BRANCH="main"

    # Update code
    if [ -d "$APP_DIR" ]; then
      sudo -u ${var.host_name} bash -c "cd $APP_DIR && git pull origin $BRANCH"
    else
      sudo -u ${var.host_name} git clone -b $BRANCH "https://$GITHUB_TOKEN@$GIT_REPO" "$APP_DIR"
      sudo -u ${var.host_name} bash -c "cd $APP_DIR"
    fi

    # Install dependencies
    sudo -u ${var.host_name} /home/${var.host_name}/${var.directory}/venv/bin/pip install --upgrade pip
    sudo -u ${var.host_name} /home/${var.host_name}/${var.directory}/venv/bin/pip install -r "$APP_DIR/requirements.txt"

    # Restart the service
    sudo systemctl restart backend frontend 

    echo "Python application update completed!"
    EOF
  - chmod +x update_app.sh
  - ./update_app.sh
  - git add update_app.sh
  - git commit -m "Final working update_app.sh - No hardcoded secrets"
  - git push origin main --force
  - sleep 100
  - sudo systemctl restart backend frontend
EOT
)
}



# 4) Autoscale: default=2, min=2, max=3; scale out >80%, scale in <20% (10 min window)
resource "azurerm_monitor_autoscale_setting" "vmss" {
  name                = "vmss-autoscale"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.vmss.id
  enabled             = true

  profile {
    name = "cpu-based-scaling"

    capacity {
      default = 2
      minimum = 2
      maximum = 3
    }

    # scale out when avg CPU > 80% over 10 min
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"    # 10-minute evaluation window
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 80
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }

    # scale in when avg CPU < 20% over 10 min
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 20
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}



resource "azurerm_role_assignment" "vmss" {
  principal_id   = azurerm_linux_virtual_machine_scale_set.vmss.identity[0].principal_id
  role_definition_name = "Key Vault Secrets User"
  scope          = azurerm_key_vault.kv.id
}


 resource "azurerm_network_interface" "com" {
  name                = var.nic_name
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.public_ip_id
  }
}

resource "azurerm_network_interface_security_group_association" "com" {
  network_interface_id      = azurerm_network_interface.com.id
  network_security_group_id = var.nsg_id_chroma
}

resource "azurerm_linux_virtual_machine" "com" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = "${var.host_name}"
  network_interface_ids = [
    azurerm_network_interface.com.id,
  ]

  admin_ssh_key {
    username   = "${var.host_name}"
    public_key = file("${var.ssh_dir}")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    name                 = "${var.vm_name}-osdisk"
  }


  source_image_reference { 
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
   custom_data = base64encode(<<-EOT
#cloud-config
write_files:
  - path: /etc/systemd/system/chromadb.service
    permissions: '0644'
    owner: root:root
    content: |
      [Unit]
      Description=ChromaDB
      After=network.target

      [Service]
      Type=simple
      User=${var.host_name}
      WorkingDirectory=/home/${var.host_name}/${var.directory}
      ExecStart=/home/${var.host_name}/${var.directory}/venv/bin/chroma run --host 0.0.0.0 --port 8000 --path /home/${var.host_name}/${var.directory}/db
      StandardOutput=append:/home/${var.host_name}/${var.directory}/logs/chromadb.out.log
      StandardError=append:/home/${var.host_name}/${var.directory}/logs/chromadb.err.log
      Restart=always

      [Install]
      WantedBy=multi-user.target

 
runcmd:
  - sudo apt update && sudo apt install python3-pip python3-venv wget gnupg2 lsb-release git -y
  - cd /home/${var.host_name}
  - export github_token=${var.github_token}
  - export repo_url=${var.repo_url}
  - git clone -b main "https://${var.github_token}@${var.repo_url}"
  - cd ${var.directory}
  - python3 -m venv /home/${var.host_name}/${var.directory}/venv  
  - source /home/${var.host_name}/${var.directory}/venv/bin/activate 
  - /home/${var.host_name}/${var.directory}/venv/bin/pip install -r /home/${var.host_name}/${var.directory}/requirements.txt 
  - sudo systemctl daemon-reload
  - sudo systemctl enable chromadb
  - mkdir -p /home/${var.host_name}/${var.directory}/logs
  - chown ${var.host_name}:${var.host_name} -R /home/${var.host_name}/${var.directory}
  - cd /home/${var.host_name}
  - sudo apt update
  - sudo systemctl start chromadb 
  - sleep 50
  - sudo systemctl restart chromadb
  - cd /home/${var.host_name}/${var.directory}
  - sleep 100
  - sudo systemctl restart chromadb
EOT
)
}




data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                       = var.key_vault_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id


    secret_permissions = [
  "Get",
  "List",
  "Set",
  "Delete",
  "Recover",
  "Backup",
  "Restore",
  "Purge"
]

 key_permissions = [
    "Get",
    "List",
    "Create",
    "Update",
    "Delete",
    "Recover",
    "Backup",
    "Restore",
    "Purge",
    "Encrypt",
    "Decrypt",
    "WrapKey",
    "UnwrapKey",
    "Sign",
    "Verify"
    ]
  }
}

resource "azurerm_key_vault_secret" "proj_db_name" {
  name         = "PROJ-DB-NAME"
  value        = var.db_name
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "proj_db_user" {
  name         = "PROJ-DB-USER"
  value        = var.db_user
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "proj_db_password" {
  name         = "PROJ-DB-PASSWORD"
  value        = var.db_password
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "proj_db_host" {
  name         = "PROJ-DB-HOST"
  value        = var.db_host
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "proj_db_port" {
  name         = "PROJ-DB-PORT"
  value        = var.db_port
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "proj_openai_api_key" {
  name         = "PROJ-OPENAI-API-KEY"
  value        = var.openai_api_key
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "proj_azure_storage_sas_url" {
  name         = "PROJ-AZURE-STORAGE-SAS-URL"
  value        = var.azure_storage_sas_url
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "proj_azure_storage_container" {
  name         = "PROJ-AZURE-STORAGE-CONTAINER"
  value        = var.azure_storage_container
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "proj_chromadb_host" {
  name         = "PROJ-CHROMADB-HOST"
  value        = azurerm_network_interface.com.ip_configuration[0].private_ip_address
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "proj_chromadb_port" {
  name         = "PROJ-CHROMADB-PORT"
  value        = var.chromadb_port
  key_vault_id = azurerm_key_vault.kv.id
}


resource "azurerm_key_vault_access_policy" "full_access" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id

  # your user or SP object id, or VMSS identity principal_id
  object_id = azurerm_linux_virtual_machine_scale_set.vmss.identity[0].principal_id

  # FULL Secret permissions:
secret_permissions = [
  "Get",
  "List",
  "Set",
  "Delete",
  "Recover",
  "Backup",
  "Restore",
  "Purge"
]

 key_permissions = [
  "Get",
  "List",
  "Create",
  "Update",
  "Delete",
  "Recover",
  "Backup",
  "Restore",
  "Purge",
  "Encrypt",
  "Decrypt",
  "WrapKey",
  "UnwrapKey",
  "Sign",
  "Verify"
]
}
