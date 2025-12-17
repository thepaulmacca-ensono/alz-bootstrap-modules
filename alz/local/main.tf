# Shared resource names (uses primary landing zone and primary region)
module "resource_names" {
  source                = "../../modules/resource_names"
  azure_location        = local.primary_region
  environment_name      = lookup(local.landing_zone_short_names, local.primary_landing_zone, local.primary_landing_zone)
  environment_name_long = local.primary_landing_zone
  service_name          = var.service_name
  postfix_number        = var.postfix_number
  resource_names        = merge(var.resource_names, local.custom_role_definitions_terraform_names)
}

# Per-landing-zone resource names (uses primary region)
module "resource_names_per_landing_zone" {
  source   = "../../modules/resource_names"
  for_each = toset(local.effective_landing_zones)

  azure_location        = local.primary_region
  environment_name      = lookup(local.landing_zone_short_names, each.key, each.key)
  environment_name_long = each.key
  service_name          = var.service_name
  postfix_number        = var.postfix_number
  resource_names        = merge(var.resource_names, local.custom_role_definitions_terraform_names)
}

# Per-landing-zone-per-region resource names (for storage accounts keyed by "lz-region")
module "resource_names_per_landing_zone_region" {
  source   = "../../modules/resource_names"
  for_each = local.landing_zone_region_combinations

  azure_location        = each.value.region
  environment_name      = lookup(local.landing_zone_short_names, each.value.landing_zone, each.value.landing_zone)
  environment_name_long = each.value.landing_zone
  service_name          = var.service_name
  postfix_number        = var.postfix_number
  resource_names        = merge(var.resource_names, local.custom_role_definitions_terraform_names)
}

module "files" {
  source                            = "../../modules/files"
  starter_module_folder_path        = local.starter_module_folder_path
  additional_files                  = var.additional_files
  configuration_file_path           = var.configuration_file_path
  built_in_configuration_file_names = var.built_in_configuration_file_names
  additional_folders_path           = var.additional_folders_path
}

module "azure" {
  source                                               = "../../modules/azure"
  count                                                = var.create_bootstrap_resources_in_azure ? 1 : 0
  user_assigned_managed_identities                     = local.managed_identities
  federated_credentials                                = local.federated_credentials
  resource_group_identity_names                        = local.resource_group_identity_names
  create_storage_account                               = true
  storage_accounts                                     = local.storage_accounts
  azure_location                                       = local.primary_region
  target_subscriptions                                 = local.target_subscriptions
  root_parent_management_group_id                      = local.root_parent_management_group_id
  storage_account_replication_type                     = var.storage_account_replication_type
  use_self_hosted_agents                               = false
  use_private_networking                               = false
  custom_role_definitions                              = local.custom_role_definitions_terraform
  role_assignments                                     = var.role_assignments_terraform
  additional_role_assignment_principal_ids             = var.grant_permissions_to_current_user ? { current_user = data.azurerm_client_config.current.object_id } : {}
  storage_account_blob_soft_delete_enabled             = var.storage_account_blob_soft_delete_enabled
  storage_account_blob_soft_delete_retention_days      = var.storage_account_blob_soft_delete_retention_days
  storage_account_blob_versioning_enabled              = var.storage_account_blob_versioning_enabled
  resource_group_lock_enabled                          = var.resource_group_lock_enabled
  storage_account_container_soft_delete_enabled        = var.storage_account_container_soft_delete_enabled
  storage_account_container_soft_delete_retention_days = var.storage_account_container_soft_delete_retention_days
  tenant_role_assignment_enabled                       = false
  tenant_role_assignment_role_definition_name          = ""
}

module "file_manipulation" {
  source                           = "../../modules/file_manipulation"
  for_each                         = toset(local.effective_landing_zones)
  vcs_type                         = "local"
  files                            = module.files.files
  resource_names                   = local.resource_names
  module_folder_path               = local.starter_module_folder_path
  starter_module_name              = local.starter_module_names_per_landing_zone[each.key]
  root_module_folder_relative_path = var.root_module_folder_relative_path
  pipeline_target_folder_name      = local.script_target_folder_name
  pipeline_files_directory_path    = "${path.module}/templates"
  subscription_ids                 = var.subscription_ids
  root_parent_management_group_id  = var.root_parent_management_group_id
  regions                          = local.regions_for_templates
}

resource "local_file" "alz" {
  for_each = local.all_repository_files
  content  = each.value.content
  filename = each.value.filename
}

resource "local_file" "command" {
  content  = local.command_final
  filename = "${local.target_directory}/scripts/deploy-local.ps1"
}
