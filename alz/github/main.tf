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
  source                                                    = "../../modules/azure"
  user_assigned_managed_identities                          = local.managed_identities
  federated_credentials                                     = local.federated_credentials
  resource_group_identity_names                             = local.resource_group_identity_names
  resource_group_agents_name                                = local.resource_names.resource_group_agents
  resource_group_network_name                               = local.resource_names.resource_group_network
  create_storage_account                                    = true
  storage_accounts                                          = local.storage_accounts
  azure_location                                            = local.primary_region
  target_subscriptions                                      = local.target_subscriptions
  root_parent_management_group_id                           = local.root_parent_management_group_id
  agent_container_instances                                 = local.runner_container_instances
  agent_container_instance_managed_identity_name            = local.resource_names.container_instance_managed_identity
  agent_organization_url                                    = local.runner_organization_repository_url
  agent_token                                               = var.github_runners_personal_access_token
  agent_organization_environment_variable                   = var.runner_organization_environment_variable
  agent_pool_name                                           = local.resource_names.version_control_system_runner_group
  agent_pool_environment_variable                           = var.runner_group_environment_variable
  agent_name_environment_variable                           = var.runner_name_environment_variable
  use_agent_pool_environment_variable                       = local.use_runner_group
  agent_token_environment_variable                          = var.runner_token_environment_variable
  virtual_network_name                                      = local.resource_names.virtual_network
  virtual_network_subnet_name_container_instances           = local.resource_names.subnet_container_instances
  virtual_network_subnet_name_private_endpoints             = local.resource_names.subnet_private_endpoints
  storage_account_private_endpoint_name                     = local.resource_names.storage_account_private_endpoint
  use_private_networking                                    = local.use_private_networking
  allow_storage_access_from_my_ip                           = local.allow_storage_access_from_my_ip
  virtual_network_address_space                             = var.virtual_network_address_space
  virtual_network_subnet_address_prefix_container_instances = var.virtual_network_subnet_address_prefix_container_instances
  virtual_network_subnet_address_prefix_private_endpoints   = var.virtual_network_subnet_address_prefix_private_endpoints
  storage_account_replication_type                          = var.storage_account_replication_type
  public_ip_name                                            = local.resource_names.public_ip
  nat_gateway_name                                          = local.resource_names.nat_gateway
  use_self_hosted_agents                                    = var.use_self_hosted_runners
  container_registry_name                                   = local.resource_names.container_registry
  container_registry_private_endpoint_name                  = local.resource_names.container_registry_private_endpoint
  container_registry_image_name                             = local.resource_names.container_image_name
  container_registry_image_tag                              = var.runner_container_image_tag
  container_registry_dockerfile_name                        = var.runner_container_image_dockerfile
  container_registry_dockerfile_repository_folder_url       = local.runner_container_instance_dockerfile_url
  custom_role_definitions                                   = local.custom_role_definitions_terraform
  role_assignments                                          = var.role_assignments_terraform
  storage_account_blob_soft_delete_enabled                  = var.storage_account_blob_soft_delete_enabled
  storage_account_blob_soft_delete_retention_days           = var.storage_account_blob_soft_delete_retention_days
  storage_account_blob_versioning_enabled                   = var.storage_account_blob_versioning_enabled
  resource_group_lock_enabled                               = var.resource_group_lock_enabled
  storage_account_container_soft_delete_enabled             = var.storage_account_container_soft_delete_enabled
  storage_account_container_soft_delete_retention_days      = var.storage_account_container_soft_delete_retention_days
  tenant_role_assignment_enabled                            = false
  tenant_role_assignment_role_definition_name               = ""
}

module "github" {
  source                                       = "../../modules/github"
  domain_name                                  = var.github_organization_domain_name
  organization_name                            = var.github_organization_name
  environments                                 = local.environments
  repository_name                              = local.resource_names.version_control_system_repository
  repositories                                 = local.repositories
  use_template_repository                      = var.use_separate_repository_for_templates
  repository_name_templates                    = local.resource_names.version_control_system_repository_templates
  repository_files                             = module.file_manipulation.repository_files
  template_repository_files                    = module.file_manipulation.template_repository_files
  workflows                                    = local.workflows
  managed_identity_client_ids                  = module.azure.user_assigned_managed_identity_client_ids
  azure_tenant_id                              = data.azurerm_client_config.current.tenant_id
  azure_subscription_id                        = var.subscription_ids["management"]
  backend_azure_resource_group_name            = local.resource_names.resource_group_state
  backend_azure_storage_account_name           = local.resource_names.storage_account
  backend_azure_storage_account_container_name = local.resource_names.storage_container
  backend_storage_accounts                     = local.storage_accounts
  approvers                                    = var.apply_approvers
  create_team                                  = var.apply_approval_team_creation_enabled
  existing_team_name                           = var.apply_approval_existing_team_name
  team_name                                    = local.resource_names.version_control_system_team
  runner_group_name                            = local.resource_names.version_control_system_runner_group
  use_runner_group                             = local.use_runner_group
  default_runner_group_name                    = var.default_runner_group_name
  use_self_hosted_runners                      = var.use_self_hosted_runners
  create_branch_policies                       = var.create_branch_policies
}

module "file_manipulation" {
  source                                 = "../../modules/file_manipulation"
  for_each                               = toset(local.effective_landing_zones)
  vcs_type                               = "github"
  files                                  = module.files.files
  use_self_hosted_agents_runners         = var.use_self_hosted_runners
  resource_names                         = local.resource_names
  use_separate_repository_for_templates  = var.use_separate_repository_for_templates
  module_folder_path                     = local.starter_module_folder_path
  starter_module_name                    = local.starter_module_names_per_landing_zone[each.key]
  project_or_organization_name           = var.github_organization_name
  root_module_folder_relative_path       = var.root_module_folder_relative_path
  ci_template_file_name                  = local.ci_template_file_name
  cd_template_file_name                  = local.cd_template_file_name
  pipeline_target_folder_name            = local.target_folder_name
  subscription_ids                       = var.subscription_ids
  root_parent_management_group_id        = var.root_parent_management_group_id
  agent_pool_or_runner_configuration     = local.agent_pool_or_runner_configuration
  pipeline_files_directory_path          = local.pipeline_files_directory_path
  pipeline_template_files_directory_path = local.pipeline_template_files_directory_path
  concurrency_value                      = local.resource_names.storage_container
  enable_dependabot                      = var.enable_dependabot
  regions                                = local.regions_for_templates
}
