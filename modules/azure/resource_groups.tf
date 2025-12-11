# Per-environment state resource groups
resource "azurerm_resource_group" "state" {
  for_each = var.create_storage_account ? var.storage_accounts : {}
  name     = each.value.resource_group_name
  location = var.azure_location
}

# Per-environment identity resource groups
resource "azurerm_resource_group" "identity" {
  for_each = var.resource_group_identity_names
  name     = each.value
  location = var.azure_location
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
