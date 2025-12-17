# Per-environment variable groups
resource "azuredevops_variable_group" "alz" {
  for_each     = var.variable_groups
  project_id   = local.project_id
  name         = each.value.variable_group_name
  description  = "Terraform variables scoped to ${each.value.variable_group_name}"
  allow_access = true

  variable {
    name  = "BACKEND_AZURE_RESOURCE_GROUP_NAME"
    value = each.value.resource_group_name
  }

  variable {
    name  = "BACKEND_AZURE_STORAGE_ACCOUNT_NAME"
    value = each.value.storage_account_name
  }

  variable {
    name  = "BACKEND_AZURE_STORAGE_ACCOUNT_CONTAINER_NAME"
    value = each.value.container_name
  }
}
