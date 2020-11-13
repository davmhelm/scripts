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
