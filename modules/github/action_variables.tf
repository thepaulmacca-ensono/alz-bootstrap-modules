# Per-environment client ID (in the correct repository and environment)
resource "github_actions_environment_variable" "azure_plan_client_id" {
  for_each      = local.all_environments
  repository    = github_repository.alz[each.value.repo_key].name
  environment   = github_repository_environment.alz[each.key].environment
  variable_name = "AZURE_CLIENT_ID"
  value         = local.effective_repositories[each.value.repo_key].managed_identity_client_ids[each.value.env_key]
}

# Per-repository action variables
resource "github_actions_variable" "azure_subscription_id" {
  for_each      = local.effective_repositories
  repository    = github_repository.alz[each.key].name
  variable_name = "AZURE_SUBSCRIPTION_ID"
  value         = var.azure_subscription_id
}

resource "github_actions_variable" "azure_tenant_id" {
  for_each      = local.effective_repositories
  repository    = github_repository.alz[each.key].name
  variable_name = "AZURE_TENANT_ID"
  value         = var.azure_tenant_id
}

resource "github_actions_variable" "backend_azure_resource_group_name" {
  for_each      = local.effective_repositories
  repository    = github_repository.alz[each.key].name
  variable_name = "BACKEND_AZURE_RESOURCE_GROUP_NAME"
  value         = var.backend_azure_resource_group_name
}

resource "github_actions_variable" "backend_azure_storage_account_name" {
  for_each      = local.effective_repositories
  repository    = github_repository.alz[each.key].name
  variable_name = "BACKEND_AZURE_STORAGE_ACCOUNT_NAME"
  value         = var.backend_azure_storage_account_name
}

resource "github_actions_variable" "backend_azure_storage_account_container_name" {
  for_each      = local.effective_repositories
  repository    = github_repository.alz[each.key].name
  variable_name = "BACKEND_AZURE_STORAGE_ACCOUNT_CONTAINER_NAME"
  value         = each.value.storage_container_name
}

# Per-region action variables for multi-region deployments
locals {
  # Build a flat map of repo_key-region for per-region variables
  repo_region_combinations = {
    for combo in flatten([
      for repo_key, repo in local.effective_repositories : [
        for region_key, storage in var.backend_storage_accounts : {
          key                  = "${repo_key}-${region_key}"
          repo_key             = repo_key
          region_key           = upper(region_key)
          resource_group_name  = storage.resource_group_name
          storage_account_name = storage.storage_account_name
          container_name       = storage.container_name
        }
      ]
    ]) : combo.key => combo
  }
}

resource "github_actions_variable" "backend_azure_resource_group_name_per_region" {
  for_each      = local.repo_region_combinations
  repository    = github_repository.alz[each.value.repo_key].name
  variable_name = "BACKEND_AZURE_RESOURCE_GROUP_NAME_${each.value.region_key}"
  value         = each.value.resource_group_name
}

resource "github_actions_variable" "backend_azure_storage_account_name_per_region" {
  for_each      = local.repo_region_combinations
  repository    = github_repository.alz[each.value.repo_key].name
  variable_name = "BACKEND_AZURE_STORAGE_ACCOUNT_NAME_${each.value.region_key}"
  value         = each.value.storage_account_name
}

resource "github_actions_variable" "backend_azure_storage_account_container_name_per_region" {
  for_each      = local.repo_region_combinations
  repository    = github_repository.alz[each.value.repo_key].name
  variable_name = "BACKEND_AZURE_STORAGE_ACCOUNT_CONTAINER_NAME_${each.value.region_key}"
  value         = each.value.container_name
}
