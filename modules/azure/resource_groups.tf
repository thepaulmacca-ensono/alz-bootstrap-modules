# Per-region state resource groups
resource "azurerm_resource_group" "state" {
  for_each = var.create_storage_account ? var.storage_accounts : {}
  name     = each.value.resource_group_name
  location = lookup(each.value, "location", var.azure_location)
}

# Resource lock to prevent accidental deletion of tfstate resource groups
resource "azurerm_management_lock" "resource_group_state" {
  for_each   = var.create_storage_account && var.resource_group_lock_enabled ? var.storage_accounts : {}
  name       = "can-not-delete"
  scope      = azurerm_resource_group.state[each.key].id
  lock_level = "CanNotDelete"
  notes      = "This lock prevents accidental deletion of the resource group containing Terraform state storage. Remove this lock before attempting to delete the resource group."
}

# Per-environment identity resource groups
resource "azurerm_resource_group" "identity" {
  for_each = var.resource_group_identity_names
  name     = each.value
  location = var.azure_location
}

# Resource lock to prevent accidental deletion of identity resource groups
resource "azurerm_management_lock" "resource_group_identity" {
  for_each   = var.resource_group_lock_enabled ? var.resource_group_identity_names : {}
  name       = "can-not-delete"
  scope      = azurerm_resource_group.identity[each.key].id
  lock_level = "CanNotDelete"
  notes      = "This lock prevents accidental deletion of the resource group containing managed identities used for Azure Landing Zones deployment. Remove this lock before attempting to delete the resource group."
}

resource "azurerm_resource_group" "agents" {
  count    = var.use_self_hosted_agents ? 1 : 0
  name     = var.resource_group_agents_name
  location = var.azure_location
}

resource "azurerm_resource_group" "network" {
  count    = var.use_private_networking ? 1 : 0
  name     = var.resource_group_network_name
  location = var.azure_location
}
