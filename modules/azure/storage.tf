# Per-region storage accounts
resource "azurerm_storage_account" "alz" {
  for_each                        = var.create_storage_account ? var.storage_accounts : {}
  name                            = each.value.storage_account_name
  resource_group_name             = azurerm_resource_group.state[each.key].name
  location                        = lookup(each.value, "location", var.azure_location)
  account_tier                    = "Standard"
  account_replication_type        = var.storage_account_replication_type
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  public_network_access_enabled   = var.use_private_networking && var.use_self_hosted_agents && !var.allow_storage_access_from_my_ip ? false : true
  blob_properties {
    dynamic "delete_retention_policy" {
      for_each = var.storage_account_blob_soft_delete_enabled ? [1] : []
      content {
        days = var.storage_account_blob_soft_delete_retention_days
      }
    }
    versioning_enabled = var.storage_account_blob_versioning_enabled

    dynamic "container_delete_retention_policy" {
      for_each = var.storage_account_container_soft_delete_enabled ? [1] : []
      content {
        days = var.storage_account_container_soft_delete_retention_days
      }
    }
  }
  lifecycle {
    ignore_changes = [queue_properties, static_website]
  }
}

# Network rules for per-env storage accounts
resource "azurerm_storage_account_network_rules" "alz" {
  for_each           = var.create_storage_account && var.use_private_networking ? var.storage_accounts : {}
  storage_account_id = azurerm_storage_account.alz[each.key].id
  default_action     = "Deny"
  ip_rules           = var.allow_storage_access_from_my_ip ? [data.http.ip[0].response_body] : []
  bypass             = ["None"]
}

# Blob service for per-env storage accounts
data "azapi_resource_id" "storage_account_blob_service" {
  for_each  = var.create_storage_account ? var.storage_accounts : {}
  type      = "Microsoft.Storage/storageAccounts/blobServices@2022-09-01"
  parent_id = azurerm_storage_account.alz[each.key].id
  name      = "default"
}

# Container for per-env storage accounts
resource "azapi_resource" "storage_account_container" {
  for_each  = var.create_storage_account ? var.storage_accounts : {}
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01"
  parent_id = data.azapi_resource_id.storage_account_blob_service[each.key].id
  name      = each.value.container_name
  body = {
    properties = {
      publicAccess = "None"
    }
  }
  schema_validation_enabled = false
  depends_on                = [azurerm_storage_account_network_rules.alz]
}

# Role assignments for storage containers
# All managed identities get access to all regional storage accounts
# This enables cross-region deployment where any identity can access any region's state
resource "azurerm_role_assignment" "alz_storage_container" {
  for_each = var.create_storage_account ? {
    for pair in flatten([
      for storage_key, storage in var.storage_accounts : [
        for mi_key, mi in var.user_assigned_managed_identities :
        { key = "${storage_key}-${mi_key}", storage_key = storage_key, mi_key = mi_key }
      ]
    ]) : pair.key => pair
  } : {}
  scope                = azapi_resource.storage_account_container[each.value.storage_key].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.alz[each.value.mi_key].principal_id
}

# Reader role for storage accounts (temporary workaround for Terraform CLI issue)
# https://github.com/hashicorp/terraform/issues/36595
resource "azurerm_role_assignment" "alz_storage_reader" {
  for_each = var.create_storage_account ? {
    for pair in flatten([
      for storage_key, storage in var.storage_accounts : [
        for mi_key, mi in var.user_assigned_managed_identities :
        { key = "${storage_key}-${mi_key}", storage_key = storage_key, mi_key = mi_key }
      ]
    ]) : pair.key => pair
  } : {}
  scope                = azurerm_storage_account.alz[each.value.storage_key].id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.alz[each.value.mi_key].principal_id
}
