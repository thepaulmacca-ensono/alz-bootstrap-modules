resource "azurerm_user_assigned_identity" "alz" {
  for_each            = var.user_assigned_managed_identities
  location            = var.azure_location
  name                = each.value.name
  resource_group_name = azurerm_resource_group.identity[each.value.resource_group_key].name
}

resource "azurerm_federated_identity_credential" "alz" {
  for_each = var.federated_credentials
  name     = each.value.federated_credential_name
  # Use the same resource group as the parent managed identity
  resource_group_name = azurerm_user_assigned_identity.alz[each.value.user_assigned_managed_identity_key].resource_group_name
  audience            = [local.audience]
  issuer              = each.value.federated_credential_issuer
  parent_id           = azurerm_user_assigned_identity.alz[each.value.user_assigned_managed_identity_key].id
  subject             = each.value.federated_credential_subject
}
