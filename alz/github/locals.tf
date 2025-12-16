# Landing Zone Setup
# Compute effective landing zones - use landing_zones if set, otherwise fallback to single landing_zone
# Note: We use a predefined order to ensure 'management' is always first (for shared resources naming)
locals {
  # Canonical order for landing zones - management should always be first for shared resource naming
  canonical_landing_zone_order = ["management", "connectivity", "identity", "security"]

  # Map long landing zone names to short names for Azure resource naming
  landing_zone_short_names = {
    management   = "mgmt"
    connectivity = "conn"
    identity     = "id"
    security     = "sec"
  }

  # Filter canonical order to only include landing zones that are specified
  effective_landing_zones = var.landing_zones != null ? [
    for lz in local.canonical_landing_zone_order : lz if contains(keys(var.landing_zones), lz)
  ] : [var.landing_zone]

  # Primary landing zone is the first one (used for shared resources naming)
  # With canonical ordering, this will be 'management' when present
  primary_landing_zone = local.effective_landing_zones[0]
}

# Region Setup
# Compute effective regions from the new regions variable, with fallback to bootstrap_location
locals {
  # Build ordered list of regions (primary first, then secondary if specified)
  effective_regions = var.regions != null ? compact([
    var.regions.primary,
    var.regions.secondary
  ]) : [var.bootstrap_location]

  # Primary region for resources that don't need multi-region (e.g., identities, runners)
  primary_region = local.effective_regions[0]

  # Whether multi-region deployment is enabled
  multi_region_enabled = length(local.effective_regions) > 1

  # Landing zone + region combinations for per-LZ-per-region resources (e.g., storage accounts)
  # Keys are "landing_zone-region" (e.g., "management-uksouth", "connectivity-ukwest")
  landing_zone_region_combinations = merge([
    for lz_name in local.effective_landing_zones : {
      for region in local.effective_regions :
      "${lz_name}-${region}" => {
        landing_zone = lz_name
        region       = region
      }
    }
  ]...)

  # Regions list for workflow template generation
  # GitHub uses environment variables instead of variable groups
  # Environments are per-landing-zone (shared across regions), not per-region
  regions_for_templates = [
    for idx, region in local.effective_regions : {
      key                      = region
      variable_group_name      = "" # GitHub doesn't use variable groups
      is_primary               = idx == 0
      service_connection_plan  = "" # GitHub doesn't use service connections
      service_connection_apply = "" # GitHub doesn't use service connections
      environment_plan         = local.resource_names_per_landing_zone[local.primary_landing_zone].version_control_system_environment_plan
      environment_apply        = local.resource_names_per_landing_zone[local.primary_landing_zone].version_control_system_environment_apply
    }
  ]
}

# Resource Name Setup
locals {
  resource_names = module.resource_names.resource_names

  # Per-landing-zone resource names
  resource_names_per_landing_zone = {
    for lz_name in local.effective_landing_zones :
    lz_name => module.resource_names_per_landing_zone[lz_name].resource_names
  }

  # Per-landing-zone-per-region resource names (for storage accounts)
  # Keys are "landing_zone-region" (e.g., "management-uksouth", "connectivity-ukwest")
  resource_names_per_landing_zone_region = {
    for key, value in local.landing_zone_region_combinations :
    key => module.resource_names_per_landing_zone_region[key].resource_names
  }
}

locals {
  root_parent_management_group_id = var.root_parent_management_group_id == "" ? data.azurerm_client_config.current.tenant_id : var.root_parent_management_group_id
}

locals {
  enterprise_plan = "enterprise"
}

locals {
  iac_terraform = "terraform"
}

locals {
  use_private_networking          = var.use_self_hosted_runners && var.use_private_networking
  allow_storage_access_from_my_ip = local.use_private_networking && var.allow_storage_access_from_my_ip
}

locals {
  use_runner_group                   = var.use_runner_group && module.github.organization_plan == local.enterprise_plan && var.use_self_hosted_runners
  runner_organization_repository_url = local.use_runner_group ? local.github_organization_url : "${local.github_organization_url}/${module.github.repository_names.module}"
}

locals {
  plan_key  = "plan"
  apply_key = "apply"
}

locals {
  ci_template_file_name                  = "workflows/ci-template.yaml"
  cd_template_file_name                  = "workflows/cd-template.yaml"
  target_folder_name                     = ".github"
  self_hosted_runner_name                = local.use_runner_group ? "group: ${local.resource_names.version_control_system_runner_group}" : "self-hosted"
  agent_pool_or_runner_configuration     = var.use_self_hosted_runners ? local.self_hosted_runner_name : "ubuntu-latest"
  pipeline_files_directory_path          = "${path.module}/actions/${var.iac_type}/main"
  pipeline_template_files_directory_path = "${path.module}/actions/${var.iac_type}/templates"
}

locals {
  target_subscriptions_legacy = distinct([var.subscription_id_connectivity, var.subscription_id_identity, var.subscription_id_management])
  target_subscriptions        = length(var.subscription_ids) > 0 ? distinct(values(var.subscription_ids)) : local.target_subscriptions_legacy
}

# Per-landing-zone GitHub environments configuration
locals {
  environments_per_landing_zone = {
    for lz_name in local.effective_landing_zones : lz_name => {
      (local.plan_key)  = local.resource_names_per_landing_zone[lz_name].version_control_system_environment_plan
      (local.apply_key) = local.resource_names_per_landing_zone[lz_name].version_control_system_environment_apply
    }
  }

  # Legacy single-landing-zone format (for backwards compatibility during transition)
  environments = local.environments_per_landing_zone[local.primary_landing_zone]

  # Per-landing-zone workflows configuration
  workflows_per_landing_zone = {
    for lz_name in local.effective_landing_zones : lz_name => {
      ci = {
        workflow_file_name = "${local.target_folder_name}/${local.ci_template_file_name}"
        environment_user_assigned_managed_identity_mappings = [
          {
            environment_key                    = local.plan_key
            user_assigned_managed_identity_key = local.plan_key
          }
        ]
      }
      cd = {
        workflow_file_name = "${local.target_folder_name}/${local.cd_template_file_name}"
        environment_user_assigned_managed_identity_mappings = [
          {
            environment_key                    = local.plan_key
            user_assigned_managed_identity_key = local.plan_key
          },
          {
            environment_key                    = local.apply_key
            user_assigned_managed_identity_key = local.apply_key
          }
        ]
      }
    }
  }

  # Per-landing-zone managed identity client IDs map (keyed by plan/apply)
  managed_identity_client_ids_per_landing_zone = {
    for lz_name in local.effective_landing_zones : lz_name => {
      (local.plan_key)  = module.azure.user_assigned_managed_identity_client_ids[length(local.effective_landing_zones) == 1 ? local.plan_key : "${lz_name}-${local.plan_key}"]
      (local.apply_key) = module.azure.user_assigned_managed_identity_client_ids[length(local.effective_landing_zones) == 1 ? local.apply_key : "${lz_name}-${local.apply_key}"]
    }
  }

  # Multi-landing-zone repositories map for github module
  # Used when landing_zones contains more than one landing zone
  repositories = length(local.effective_landing_zones) == 1 ? null : {
    for lz_name in local.effective_landing_zones : lz_name => {
      repository_name             = local.resource_names_per_landing_zone[lz_name].version_control_system_repository
      repository_files            = module.file_manipulation.repository_files # TODO: Per-landing-zone files
      environments                = local.environments_per_landing_zone[lz_name]
      workflows                   = local.workflows_per_landing_zone[lz_name]
      managed_identity_client_ids = local.managed_identity_client_ids_per_landing_zone[lz_name]
      storage_container_name      = local.resource_names_per_landing_zone[lz_name].storage_container
    }
  }
}

# Managed identities - currently single landing zone, prepared for multi-landing-zone expansion
# When multi-landing-zone is enabled, keys will be like "mgmt-plan", "connectivity-plan", etc.
locals {
  managed_identities = length(local.effective_landing_zones) == 1 ? {
    # Single landing zone - use simple keys for backwards compatibility
    (local.plan_key) = {
      name               = local.resource_names_per_landing_zone[local.primary_landing_zone].user_assigned_managed_identity_plan
      resource_group_key = local.primary_landing_zone
    }
    (local.apply_key) = {
      name               = local.resource_names_per_landing_zone[local.primary_landing_zone].user_assigned_managed_identity_apply
      resource_group_key = local.primary_landing_zone
    }
    } : merge([
      # Multi-landing-zone - use prefixed keys
      for lz_name in local.effective_landing_zones : {
        "${lz_name}-${local.plan_key}" = {
          name               = local.resource_names_per_landing_zone[lz_name].user_assigned_managed_identity_plan
          resource_group_key = lz_name
        }
        "${lz_name}-${local.apply_key}" = {
          name               = local.resource_names_per_landing_zone[lz_name].user_assigned_managed_identity_apply
          resource_group_key = lz_name
        }
      }
  ]...)

  # Per-landing-zone identity resource groups
  resource_group_identity_names = {
    for lz_name in local.effective_landing_zones :
    lz_name => local.resource_names_per_landing_zone[lz_name].resource_group_identity
  }

  # Per-landing-zone-per-region storage accounts
  # Keys are "landing_zone-region" (e.g., "management-uksouth", "connectivity-ukwest")
  storage_accounts = {
    for key, value in local.landing_zone_region_combinations :
    key => {
      resource_group_name  = local.resource_names_per_landing_zone_region[key].resource_group_state
      storage_account_name = local.resource_names_per_landing_zone_region[key].storage_account
      container_name       = local.resource_names_per_landing_zone_region[key].storage_container
      location             = value.region
    }
  }

  # Federated credentials - maps managed identity keys to their OIDC subjects/issuers
  federated_credentials = length(local.effective_landing_zones) == 1 ? {
    # Single landing zone - use existing module.github output structure
    for key, value in module.github.subjects :
    key => {
      user_assigned_managed_identity_key = value.user_assigned_managed_identity_key
      federated_credential_subject       = value.subject
      federated_credential_issuer        = module.github.issuer
      federated_credential_name          = "${local.resource_names_per_landing_zone[local.primary_landing_zone].user_assigned_managed_identity_federated_credentials_prefix}-${key}"
    }
    } : merge([
      # Multi-landing-zone - use prefixed keys matching the github module output
      for key, value in module.github.subjects : {
        (key) = {
          user_assigned_managed_identity_key = value.user_assigned_managed_identity_key
          federated_credential_subject       = value.subject
          federated_credential_issuer        = module.github.issuer
          # Extract lz_name from the subject key (format: "lz_name-workflow_key-identity_key")
          federated_credential_name = "${local.resource_names_per_landing_zone[split("-", key)[0]].user_assigned_managed_identity_federated_credentials_prefix}-${key}"
        }
      }
  ]...)

  runner_container_instances = var.use_self_hosted_runners ? {
    agent_01 = {
      container_instance_name = local.resource_names.container_instance_01
      agent_name              = local.resource_names.runner_01
      cpu                     = var.runner_container_cpu
      memory                  = var.runner_container_memory
      cpu_max                 = var.runner_container_cpu_max
      memory_max              = var.runner_container_memory_max
      zones                   = var.runner_container_zone_support ? ["1"] : []
    }
    agent_02 = {
      container_instance_name = local.resource_names.container_instance_02
      agent_name              = local.resource_names.runner_02
      cpu                     = var.runner_container_cpu
      memory                  = var.runner_container_memory
      cpu_max                 = var.runner_container_cpu_max
      memory_max              = var.runner_container_memory_max
      zones                   = var.runner_container_zone_support ? ["2"] : []
    }
  } : {}
}

locals {
  starter_module_folder_path = var.module_folder_path_relative ? ("${path.module}/${var.module_folder_path}") : var.module_folder_path
}

locals {
  runner_container_instance_dockerfile_url = "${var.runner_container_image_repository}#${var.runner_container_image_tag}:${var.runner_container_image_folder}"
}

locals {
  custom_role_definitions_bicep_names         = { for key, value in var.custom_role_definitions_bicep : "custom_role_definition_bicep_${key}" => value.name }
  custom_role_definitions_terraform_names     = { for key, value in var.custom_role_definitions_terraform : "custom_role_definition_terraform_${key}" => value.name }
  custom_role_definitions_bicep_classic_names = { for key, value in var.custom_role_definitions_bicep_classic : "custom_role_definition_bicep_classic_${key}" => value.name }

  custom_role_definitions_bicep = {
    for key, value in var.custom_role_definitions_bicep : key => {
      name        = local.resource_names["custom_role_definition_bicep_${key}"]
      description = value.description
      permissions = value.permissions
    }
  }

  custom_role_definitions_terraform = {
    for key, value in var.custom_role_definitions_terraform : key => {
      name        = local.resource_names["custom_role_definition_terraform_${key}"]
      description = value.description
      permissions = value.permissions
    }
  }

  custom_role_definitions_bicep_classic = {
    for key, value in var.custom_role_definitions_bicep_classic : key => {
      name        = local.resource_names["custom_role_definition_bicep_classic_${key}"]
      description = value.description
      permissions = value.permissions
    }
  }
}

locals {
  github_organization_url = "${var.github_organization_scheme}://${var.github_organization_domain_name}/${var.github_organization_name}"
  github_api_base_url     = var.github_api_domain_name == "" ? "${var.github_organization_scheme}://api.${var.github_organization_domain_name}/" : "${var.github_organization_scheme}://${var.github_api_domain_name}/"
}
