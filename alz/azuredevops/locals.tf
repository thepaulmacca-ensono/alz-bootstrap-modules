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

  # Per-landing-zone starter module names
  # Uses the per-LZ override if set, otherwise falls back to the global starter_module_name
  starter_module_names_per_landing_zone = {
    for lz_name in local.effective_landing_zones :
    lz_name => var.landing_zones != null ? coalesce(
      try(var.landing_zones[lz_name].starter_module_name, null),
      var.starter_module_name
    ) : var.starter_module_name
  }
}

# Region Setup
# Compute effective regions from the new regions variable, with fallback to bootstrap_location
locals {
  # Build ordered list of regions (primary first, then secondary if specified)
  effective_regions = var.regions != null ? compact([
    var.regions.primary,
    var.regions.secondary
  ]) : [var.bootstrap_location]

  # Primary region for resources that don't need multi-region (e.g., identities, agents)
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

  # Regions list for pipeline template generation
  # Uses primary landing zone's variable groups - each region maps to its variable group
  # Service connections and environments are shared per-landing-zone (not per-region)
  regions_for_templates = [
    for idx, region in local.effective_regions : {
      key                      = region
      variable_group_name      = local.variable_groups["${local.primary_landing_zone}-${region}"].variable_group_name
      is_primary               = idx == 0
      service_connection_plan  = local.environments_per_landing_zone[local.primary_landing_zone][local.plan_key].service_connection_name
      service_connection_apply = local.environments_per_landing_zone[local.primary_landing_zone][local.apply_key].service_connection_name
      environment_plan         = local.environments_per_landing_zone[local.primary_landing_zone][local.plan_key].environment_name
      environment_apply        = local.environments_per_landing_zone[local.primary_landing_zone][local.apply_key].environment_name
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
  use_private_networking          = var.use_self_hosted_agents && var.use_private_networking
  allow_storage_access_from_my_ip = local.use_private_networking && var.allow_storage_access_from_my_ip
}

locals {
  plan_key  = "plan"
  apply_key = "apply"
}

locals {
  ci_file_name          = "ci.yaml"
  cd_file_name          = "cd.yaml"
  ci_template_file_name = "ci-template.yaml"
  cd_template_file_name = "cd-template.yaml"
  target_folder_name    = ".pipelines"

  agent_pool_or_runner_configuration     = var.use_self_hosted_agents ? "name: ${local.resource_names.version_control_system_agent_pool}" : "vmImage: ubuntu-latest"
  pipeline_files_directory_path          = "${path.module}/pipelines/main"
  pipeline_template_files_directory_path = "${path.module}/pipelines/templates"
}

locals {
  target_subscriptions_legacy = distinct([var.subscription_id_connectivity, var.subscription_id_identity, var.subscription_id_management])
  target_subscriptions        = length(var.subscription_ids) > 0 ? distinct(values(var.subscription_ids)) : local.target_subscriptions_legacy
}

# Managed identities - keys are prefixed with landing zone: "mgmt-plan", "conn-apply", etc.
# Each identity includes name and resource_group_key to support per-landing-zone resource groups
locals {
  managed_identities = merge([
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

  # Per-landing-zone-per-region variable groups
  # Keys are "landing_zone-region" (e.g., "management-uksouth", "connectivity-ukwest")
  # Each variable group contains backend configuration for its specific landing zone and region
  variable_groups = {
    for key, value in local.landing_zone_region_combinations :
    key => {
      landing_zone         = value.landing_zone
      region               = value.region
      variable_group_name  = "${local.resource_names_per_landing_zone[value.landing_zone].version_control_system_variable_group}-${value.region}"
      resource_group_name  = local.resource_names_per_landing_zone_region[key].resource_group_state
      storage_account_name = local.resource_names_per_landing_zone_region[key].storage_account
      container_name       = local.resource_names_per_landing_zone_region[key].storage_container
    }
  }

  # Federated credentials - maps managed identity keys to their OIDC subjects/issuers
  # One federated credential per managed identity (per-landing-zone), shared across regions
  federated_credentials = merge([
    for lz_name in local.effective_landing_zones : {
      "${lz_name}-${local.plan_key}" = {
        user_assigned_managed_identity_key = "${lz_name}-${local.plan_key}"
        federated_credential_subject       = module.azure_devops.subjects["${lz_name}-${local.plan_key}"]
        federated_credential_issuer        = module.azure_devops.issuers["${lz_name}-${local.plan_key}"]
        federated_credential_name          = local.resource_names_per_landing_zone[lz_name].user_assigned_managed_identity_federated_credentials_plan
      }
      "${lz_name}-${local.apply_key}" = {
        user_assigned_managed_identity_key = "${lz_name}-${local.apply_key}"
        federated_credential_subject       = module.azure_devops.subjects["${lz_name}-${local.apply_key}"]
        federated_credential_issuer        = module.azure_devops.issuers["${lz_name}-${local.apply_key}"]
        federated_credential_name          = local.resource_names_per_landing_zone[lz_name].user_assigned_managed_identity_federated_credentials_apply
      }
    }
  ]...)

  agent_container_instances = var.use_self_hosted_agents ? {
    agent_01 = {
      container_instance_name = local.resource_names.container_instance_01
      agent_name              = local.resource_names.agent_01
      cpu                     = var.agent_container_cpu
      memory                  = var.agent_container_memory
      cpu_max                 = var.agent_container_cpu_max
      memory_max              = var.agent_container_memory_max
      zones                   = var.agent_container_zone_support ? ["1"] : []
    }
    agent_02 = {
      container_instance_name = local.resource_names.container_instance_02
      agent_name              = local.resource_names.agent_02
      cpu                     = var.agent_container_cpu
      memory                  = var.agent_container_memory
      cpu_max                 = var.agent_container_cpu_max
      memory_max              = var.agent_container_memory_max
      zones                   = var.agent_container_zone_support ? ["2"] : []
    }
  } : {}
}

# Per-landing-zone Azure DevOps environments configuration
# Environments and service connections are per-landing-zone (shared across regions)
# Pipeline stages use the same service connection for all regional deployments
locals {
  # Per-landing-zone environments (shared across regions)
  environments_per_landing_zone = {
    for lz_name in local.effective_landing_zones : lz_name => {
      (local.plan_key) = {
        environment_name        = local.resource_names_per_landing_zone[lz_name].version_control_system_environment_plan
        service_connection_name = local.resource_names_per_landing_zone[lz_name].version_control_system_service_connection_plan
        service_connection_required_templates = [
          "${local.target_folder_name}/${local.ci_template_file_name}",
          "${local.target_folder_name}/${local.cd_template_file_name}"
        ]
      }
      (local.apply_key) = {
        environment_name        = local.resource_names_per_landing_zone[lz_name].version_control_system_environment_apply
        service_connection_name = local.resource_names_per_landing_zone[lz_name].version_control_system_service_connection_apply
        service_connection_required_templates = [
          "${local.target_folder_name}/${local.cd_template_file_name}"
        ]
      }
    }
  }

  # Per-landing-zone pipelines configuration
  # For multi-region deployments, pipelines still have sequential regional stages,
  # but they all use the same per-LZ service connections and environments
  pipelines_per_landing_zone = {
    for lz_name in local.effective_landing_zones : lz_name => merge(
      {
        ci = {
          pipeline_name           = local.resource_names_per_landing_zone[lz_name].version_control_system_pipeline_name_ci
          pipeline_file_name      = "${local.target_folder_name}/${local.ci_file_name}"
          environment_keys        = [local.plan_key]
          service_connection_keys = [local.plan_key]
        }
        cd = {
          pipeline_name           = local.resource_names_per_landing_zone[lz_name].version_control_system_pipeline_name_cd
          pipeline_file_name      = "${local.target_folder_name}/${local.cd_file_name}"
          environment_keys        = [local.plan_key, local.apply_key]
          service_connection_keys = [local.plan_key, local.apply_key]
        }
      },
      var.enable_renovate ? {
        renovate = {
          pipeline_name           = local.resource_names_per_landing_zone[lz_name].version_control_system_pipeline_name_renovate
          pipeline_file_name      = "${local.target_folder_name}/${local.renovate_file_name}"
          environment_keys        = []
          service_connection_keys = []
        }
      } : {}
    )
  }

  # Per-landing-zone managed identity client IDs map (keyed by plan/apply)
  managed_identity_client_ids_per_landing_zone = {
    for lz_name in local.effective_landing_zones : lz_name => {
      (local.plan_key)  = module.azure.user_assigned_managed_identity_client_ids["${lz_name}-${local.plan_key}"]
      (local.apply_key) = module.azure.user_assigned_managed_identity_client_ids["${lz_name}-${local.apply_key}"]
    }
  }

  # Multi-landing-zone repositories map for azure_devops module
  repositories = {
    for lz_name in local.effective_landing_zones : lz_name => {
      repository_name             = local.resource_names_per_landing_zone[lz_name].version_control_system_repository
      repository_files            = module.file_manipulation[lz_name].repository_files
      environments                = local.environments_per_landing_zone[lz_name]
      pipelines                   = local.pipelines_per_landing_zone[lz_name]
      managed_identity_client_ids = local.managed_identity_client_ids_per_landing_zone[lz_name]
      storage_container_name      = local.resource_names_per_landing_zone[lz_name].storage_container
    }
  }
}

locals {
  starter_module_folder_path = var.module_folder_path_relative ? ("${path.module}/${var.module_folder_path}") : var.module_folder_path
}

locals {
  agent_container_instance_dockerfile_url = "${var.agent_container_image_repository}#${var.agent_container_image_tag}:${var.agent_container_image_folder}"
}

locals {
  custom_role_definitions_terraform_names = { for key, value in var.custom_role_definitions_terraform : "custom_role_definition_terraform_${key}" => value.name }

  custom_role_definitions_terraform = {
    for key, value in var.custom_role_definitions_terraform : key => {
      name        = local.resource_names["custom_role_definition_terraform_${key}"]
      description = value.description
      permissions = value.permissions
    }
  }
}

# Role assignments expansion - identity keys are prefixed: "mgmt-plan", "conn-apply", etc.
# This local expands the base role assignments to cover all landing zone identities
locals {
  role_assignments_terraform_expanded = merge([
    for lz_name in local.effective_landing_zones : {
      for key, value in var.role_assignments_terraform :
      "${lz_name}-${key}" => {
        custom_role_definition_key         = value.custom_role_definition_key
        user_assigned_managed_identity_key = "${lz_name}-${value.user_assigned_managed_identity_key}"
        scope                              = value.scope
      }
    }
  ]...)
}
