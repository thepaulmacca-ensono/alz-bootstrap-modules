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
  ]) : (var.bootstrap_location != null && var.bootstrap_location != "" ? [var.bootstrap_location] : [])

  # Primary region for resources that don't need multi-region (e.g., identities, agents)
  primary_region = length(local.effective_regions) > 0 ? local.effective_regions[0] : ""

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

  # Regions list for script template generation
  # Local module doesn't use CI/CD pipelines, but still passes regions for consistency
  regions_for_templates = [
    for idx, region in local.effective_regions : {
      key                      = region
      variable_group_name      = "" # Local doesn't use variable groups
      is_primary               = idx == 0
      service_connection_plan  = "" # Local doesn't use service connections
      service_connection_apply = "" # Local doesn't use service connections
      environment_plan         = "" # Local doesn't use environments
      environment_apply        = "" # Local doesn't use environments
    }
  ]

  # Per-landing-zone starter module names
  # Allows each landing zone to use a different starter module (e.g., management uses platform_landing_zone, connectivity uses hubnetworking)
  starter_module_names_per_landing_zone = {
    for lz_name in local.effective_landing_zones :
    lz_name => coalesce(
      try(var.landing_zones[lz_name].starter_module_name, null),
      var.starter_module_name
    )
  }
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
  plan_key  = "plan"
  apply_key = "apply"
}

locals {
  target_subscriptions_legacy = distinct([var.subscription_id_connectivity, var.subscription_id_identity, var.subscription_id_management])
  target_subscriptions        = length(var.subscription_ids) > 0 ? distinct(values(var.subscription_ids)) : local.target_subscriptions_legacy
}

# Managed identities - keys are prefixed with landing zone: "management-plan", "connectivity-apply", etc.
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

  federated_credentials = var.federated_credentials
}

locals {
  starter_module_folder_path = var.module_folder_path_relative ? ("${path.module}/${var.module_folder_path}") : var.module_folder_path
}

locals {
  target_directory          = var.target_directory == "" ? ("${path.module}/${var.default_target_directory}") : var.target_directory
  script_target_folder_name = "scripts"

  # Combine all repository files across landing zones for local file creation
  # For single landing zone: files go directly to target_directory (backwards compatible)
  # For multiple landing zones: each landing zone gets its own subdirectory (e.g., target_directory/management/)
  all_repository_files = length(local.effective_landing_zones) == 1 ? {
    # Single landing zone - flat structure for backwards compatibility
    for file_key, file_value in module.file_manipulation[local.primary_landing_zone].repository_files :
    file_key => {
      content  = file_value.content
      filename = "${local.target_directory}/${file_key}"
    }
    } : merge([
      # Multiple landing zones - each in its own subdirectory
      for lz_name in local.effective_landing_zones : {
        for file_key, file_value in module.file_manipulation[lz_name].repository_files :
        "${lz_name}/${file_key}" => {
          content  = file_value.content
          filename = "${local.target_directory}/${lz_name}/${file_key}"
        }
      }
  ]...)
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
