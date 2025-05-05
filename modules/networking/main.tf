resource "azurerm_virtual_network" "networking" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "networking" {
  name                 = var.subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.networking.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "appgw" {
  name                 = var.subnet_name_appgw
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.networking.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "networking" {
  name                = var.public_ip_name
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "chroma" {
  name                = var.nsg_name_chroma
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "AllowAny8000PortInpound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
resource "azurerm_network_security_group" "vmss" {
  name                = var.nsg_name_vmss
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "AllowSSHPort22Inpound"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
    security_rule {
    name                       = "AllowAny8501PortInpound"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8501"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}



###############################
# 1) Public IP for Front-End #
###############################
resource "azurerm_public_ip" "appgw_pip" {
  name                = "appgw-public-ip"
  resource_group_name = var.resource_group_name
  location            = var.location

  sku               = "Standard"
  allocation_method = "Static"

  # availability zones for the public IP
  zones = ["1","2","3"]                             

  # only IPv4
  #public_ip_address_version = "IPv4"            
}

#######################################
# 2) Application Gateway (Standard_v2) #
#######################################
resource "azurerm_application_gateway" "appgw" {
  name                = "appgatewaysda"
  resource_group_name = var.resource_group_name
  location            = var.location

  # spread across zones 1,2,3
  zones               = ["1","2","3"]              

  sku {
    name = "Standard_v2"                         
    tier = "Standard_v2"
  }

  # 1) autoscale between 0 and 10 instances
  autoscale_configuration {
    min_capacity = 0                          
    max_capacity = 10
  }

  # 4) enable HTTP/2
  enable_http2 = true                           

  #############################
  # gateway IP (in your VNet) #
  #############################
  gateway_ip_configuration {
    name      = "appgw-gateway-ip"
    subnet_id = azurerm_subnet.appgw.id      # you must have created an “agw_subnet” in your VNet
  }

  #################################
  # front-end listens on public IP #
  #################################
  frontend_ip_configuration {
    name                 = "appgw-frontend-ip"
    public_ip_address_id = azurerm_public_ip.appgw_pip.id 
  }

  ##################
  # listener port 80 #
  ##################
  frontend_port {
    name = "port-80"
    port = 80                                   # <— point 8
  }

  http_listener {
    name                           = "listener-80"
    frontend_ip_configuration_name = "appgw-frontend-ip"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  ########################
  # back-end is your VMSS #
  ########################
  backend_address_pool {
  name = "vmss-backend-pool"                 
  
  # ip_addresses = [
  #   for inst in var.instances : 
  #   inst.var.vmss_private_ip
  # ]
}

  ##################################
  # back-end HTTP setting on port 8501 #
  ##################################
  backend_http_settings {
    name                  = "http-8501"
    protocol              = "Http"
    port                  = 8501                  # <— point 7
    cookie_based_affinity = "Disabled"
    request_timeout       = 30
  }

  ############################
  # tie listener → backend  #
  ############################
  request_routing_rule {
    name                       = "rule-80-to-8501"
    rule_type                  = "Basic"
    http_listener_name         = "listener-80"
    backend_address_pool_name  = "vmss-backend-pool"
    backend_http_settings_name = "http-8501"
    priority                   = 100 
  }
}
