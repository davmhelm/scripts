# This sample script is not supported under any Microsoft standard support program or service. 
# The sample script is provided AS IS without warranty of any kind. Microsoft further disclaims 
# all implied warranties including, without limitation, any implied warranties of merchantability 
# or of fitness for a particular purpose. The entire risk arising out of the use or performance of 
# the sample scripts and documentation remains with you. In no event shall Microsoft, its authors, 
# or anyone else involved in the creation, production, or delivery of the scripts be liable for any 
# damages whatsoever (including, without limitation, damages for loss of business profits, business 
# interruption, loss of business information, or other pecuniary loss) arising out of the use of or 
# inability to use the sample scripts or documentation, even if Microsoft has been advised of the 
# possibility of such damages 

provider "azurerm" {
  version = "~>2.0"
  features {}

  subscription_id = "{subscription_guid}"
  tenant_id       = "{aad_tenant_guid}"
}

resource "azurerm_resource_group" "example" {
  name     = "{resource_group_name}"
  location = "West US 2"

  tags = {
    environment = "dev"
  }
}

resource "azurerm_storage_account" "example" {
  name                     = "{storage_account_name}"
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = "true"
  enable_https_traffic_only = "true"
  min_tls_version          = "TLS1_2"
  allow_blob_public_access = "false"

  tags = {
    environment = "dev"
  }
}

resource "azurerm_storage_data_lake_gen2_filesystem" "example" {
  name               = "default"
  storage_account_id = azurerm_storage_account.example.id
}

resource "azurerm_synapse_workspace" "example" {
  name                                 = "{synapse_workspace_name}"
  resource_group_name                  = azurerm_resource_group.example.name
  location                             = azurerm_resource_group.example.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.example.id
  sql_administrator_login              = "{your_sql_user_here}"
  sql_administrator_login_password     = "{your_sql_pass_here}"

# https://docs.microsoft.com/en-us/azure/synapse-analytics/security/synapse-workspace-managed-vnet
  managed_virtual_network_enabled      = "true"

# Use this block to specify a different identity as the SQL AD Admin
# The identity used to deploy the resources in the TF plan is used by default
#  aad_admin {
#    login     = "AzureAD Admin"
#    object_id = "00000000-0000-0000-0000-000000000000"
#    tenant_id = "00000000-0000-0000-0000-000000000000"
#  }

  tags = {
    Env = "dev"
  }
}

# Get storage container info for ADLS Gen 2 filesystem
data "azurerm_storage_container" "example" {
  name                 = azurerm_storage_data_lake_gen2_filesystem.example.name
  storage_account_name = azurerm_storage_account.example.name

  depends_on = [azurerm_storage_account.example, azurerm_storage_data_lake_gen2_filesystem.example]
}

# Applies the required permissions to the Workspace to access the ADLS filesystem
# https://techcommunity.microsoft.com/t5/azure-synapse-analytics/synapse-workspace-permission-error/ba-p/1358045
# https://github.com/terraform-providers/terraform-provider-azurerm/issues/6221
resource "azurerm_role_assignment" "example" {
  #name                 = #Optional, let Terraform randomly generate a GUID for it
  #scope                = azurerm_storage_data_lake_gen2_filesystem.example.id
  scope                = data.azurerm_storage_container.example.resource_manager_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_synapse_workspace.example.identity[0].principal_id  
}

# Certainly you'd set your network access more tightly than this
# this rule should enable you to get to the Workspace Studio from any browser
resource "azurerm_synapse_firewall_rule" "example" {
  name                 = "AllowAll"
  synapse_workspace_id = azurerm_synapse_workspace.example.id
  start_ip_address     = "0.0.0.0"
  end_ip_address       = "255.255.255.255"
}

# Enabling "Allow access to Azure services" is achieved per Note in 
# https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/synapse_firewall_rule#argument-reference
resource "azurerm_synapse_firewall_rule" "example2" {
  name                 = "AllowAllWindowsAzureIps"
  synapse_workspace_id = azurerm_synapse_workspace.example.id
  start_ip_address     = "0.0.0.0"
  end_ip_address       = "0.0.0.0"
}

# Use blocks like this to assign access in Synapse Workspace Studio for other identities
# Useful when your TF plan is running as a service principal/managed identity
# By default, the identity creating the workspace will be added as a Workspace Admin
#resource "azurerm_synapse_role_assignment" "example" {
#  synapse_workspace_id = azurerm_synapse_workspace.example.id
#  role_name            = "Workspace Admin" # or "Sql Admin", "Apache Spark Admin"
#  principal_id         = "user principal ID/service principal object ID, in GUID format"
#}

# Use blocks like this to create SQL DW pools in addition to the 
# on-demand SQL pool you get inherently in the Synapse Workspace
#resource "azurerm_synapse_sql_pool" "example" {
#  name                 = "SQLDB1"
#  synapse_workspace_id = azurerm_synapse_workspace.example.id
#  sku_name             = "DW100c"
#  create_mode          = "Default"
#
#  tags = {
#    Env = "Dev"
#  }
#}

# Use blocks like this to create Apache Spark pools in addition to the 
# on-demand SQL pool you get inherently in the Synapse Workspace
#resource "azurerm_synapse_spark_pool" "example" {
#  name                 = "Spark1"
#  synapse_workspace_id = azurerm_synapse_workspace.example.id
#  node_size_family     = "MemoryOptimized"
#  node_size            = "Small"
#
#  auto_scale {
#    max_node_count = 5
#    min_node_count = 3
#  }
#
#  auto_pause {
#    delay_in_minutes = 15
#  }
#
#  tags = {
#    Env = "Dev"
#  }
#}

# https://docs.microsoft.com/en-us/azure/synapse-analytics/security/how-to-connect-to-workspace-from-restricted-network#step-1-add-network-outbound-security-rules-to-the-restricted-network
resource "azurerm_network_security_group" "example" {
  name                = "SynapsePrivateNetwork-nsg"
  location            = azurerm_resource_group.example.name
  resource_group_name = azurerm_resource_group.example.location

  security_rule {
    name                       = "Outbound-Allow-ARM-ServiceTag"
    priority                   = 3000
    direction                  = "Outbound"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "AzureResourceManager"
    destination_port_range     = "443"
    access                     = "Allow"
    protocol                   = "TCP"
  }

  security_rule {
    name                       = "Outbound-Allow-AFDFE-ServiceTag"
    priority                   = 3010
    direction                  = "Outbound"
    source_port_range          = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureFrontDoor.Frontend"
    destination_port_range     = "443"
    access                     = "Allow"
    protocol                   = "TCP"
  }

  security_rule {
    name                       = "Outbound-Allow-AAD-ServiceTag"
    priority                   = 3020
    direction                  = "Outbound"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "AzureActiveDirectory"
    destination_port_range     = "443"
    access                     = "Allow"
    protocol                   = "TCP"
  }

  security_rule {
    name                       = "Outbound-Allow-AzureMonitor-ServiceTag"
    priority                   = 3030
    direction                  = "Outbound"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "AzureMonitor"
    destination_port_range     = "443"
    access                     = "Allow"
    protocol                   = "TCP" 

  }

  tags = {
    Env = "Dev"
  }
}

resource "azurerm_virtual_network" "example" {
  name                = "SynapsePrivateNetwork-VNet"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  address_space       = ["10.0.0.0/16"]
  #dns_servers         = ["10.0.0.4", "10.0.0.5"] 

  subnet {
    name           = "clients"
    address_prefix = "10.0.1.0/24"
    security_group = azurerm_network_security_group.example.id
  }

  subnet {
    name           = "endpoints"
    address_prefix = "10.0.3.0/24"
    security_group = azurerm_network_security_group.example.id
  }

  tags = {
    Env = "Dev"
  }
}

# https://docs.microsoft.com/en-us/azure/synapse-analytics/security/how-to-connect-to-workspace-from-restricted-network#step-2-create-private-link-hubs
# Microsoft.Synapse/privateLinkHubs RP is not in TF yet
# Rely on template deployment with Heredocs, not ideal but workable
# https://www.terraform.io/docs/configuration/expressions.html#string-literals
resource "azurerm_resource_group_template_deployment" "example" {
  name                = format("SynapsePrivateHub-Deploy_%s", formatdate("YYYYMMDDhhmmss", timestamp())
  resource_group_name = azurerm_resource_group.example.name
  deployment_mode     = "Incremental"
  template_content    = <<TEMPLATE
{
    "$schema": "http://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.1",
    "parameters": {
        "name": {
            "type": "string"
        },
        "location": {
            "type": "string"
        },
        "tagValues": {
            "type": "object",
            "defaultValue": {}
        }
    },
    "variables": {},
    "resources": [
        {
            "apiVersion": "2019-06-01-preview",
            "name": "[parameters('name')]",
            "location": "[parameters('location')]",
            "type": "Microsoft.Synapse/privateLinkHubs",
            "identity": {
                "type": "None"
            },
            "properties": {},
            "resources": [],
            "dependsOn": [],
            "tags": "[parameters('tagValues')]"
        }
    ],
    "outputs": {}
}
TEMPLATE

  parameters_content  = <<PARAMETERS
  {
    "$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "name": {
            "value": "synapseplhub"
        },
        "location": {
            "value": "westus2"
        },
        "tagValues": {
            "value": {
                "Env": "Dev"
            }
        }
    }
}
PARAMETERS

}
