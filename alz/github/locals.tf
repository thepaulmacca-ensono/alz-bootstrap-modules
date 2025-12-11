# Environment Names Setup
# Compute effective environment names - use environment_names if set, otherwise fallback to single environment_name
# Note: We use a predefined order to ensure 'mgmt' is always first (for shared resources naming)
locals {
  # Canonical order for environments - mgmt should always be first for shared resource naming
  canonical_environment_order = ["mgmt", "conn", "id", "sec"]

  # Filter canonical order to only include environments that are specified
  effective_environment_names = var.environment_names != null ? [
    for env in local.canonical_environment_order : env if contains(keys(var.environment_names), env)
  ] : [var.environment_name]

  # Primary environment is the first one (used for shared resources naming)
  # With canonical ordering, this will be 'mgmt' when present
  primary_environment_name = local.effective_environment_names[0]
}

# Resource Name Setup
locals {
  resource_names = module.resource_names.resource_names

  # Per-environment resource names
  resource_names_per_environment = {
    for env_name in local.effective_environment_names :
    env_name => module.resource_names_per_environment[env_name].resource_names
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

# Per-environment GitHub environments configuration
locals {
  environments_per_environment = {
    for env_name in local.effective_environment_names : env_name => {
      (local.plan_key)  = local.resource_names_per_environment[env_name].version_control_system_environment_plan
      (local.apply_key) = local.resource_names_per_environment[env_name].version_control_system_environment_apply
    }
  }

  # Legacy single-environment format (for backwards compatibility during transition)
  environments = local.environments_per_environment[local.primary_environment_name]

  # Per-environment workflows configuration
  workflows_per_environment = {
    for env_name in local.effective_environment_names : env_name => {
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

  # Per-environment managed identity client IDs map (keyed by plan/apply)
  managed_identity_client_ids_per_environment = {
    for env_name in local.effective_environment_names : env_name => {
      (local.plan_key)  = module.azure.user_assigned_managed_identity_client_ids[length(local.effective_environment_names) == 1 ? local.plan_key : "${env_name}-${local.plan_key}"]
      (local.apply_key) = module.azure.user_assigned_managed_identity_client_ids[length(local.effective_environment_names) == 1 ? local.apply_key : "${env_name}-${local.apply_key}"]
    }
  }

  # Multi-environment repositories map for github module
  # Used when environment_names contains more than one environment
  repositories = length(local.effective_environment_names) == 1 ? null : {
    for env_name in local.effective_environment_names : env_name => {
      repository_name             = local.resource_names_per_environment[env_name].version_control_system_repository
      repository_files            = module.file_manipulation.repository_files # TODO: Per-environment files
      environments                = local.environments_per_environment[env_name]
      workflows                   = local.workflows_per_environment[env_name]
      managed_identity_client_ids = local.managed_identity_client_ids_per_environment[env_name]
      storage_container_name      = local.resource_names_per_environment[env_name].storage_container
    }
  }
}

# Managed identities - currently single environment, prepared for multi-environment expansion
# When multi-environment is enabled, keys will be like "mgmt-plan", "connectivity-plan", etc.
locals {
  managed_identities = length(local.effective_environment_names) == 1 ? {
    # Single environment - use simple keys for backwards compatibility
    (local.plan_key)  = local.resource_names_per_environment[local.primary_environment_name].user_assigned_managed_identity_plan
    (local.apply_key) = local.resource_names_per_environment[local.primary_environment_name].user_assigned_managed_identity_apply
    } : merge([
      # Multi-environment - use prefixed keys
      for env_name in local.effective_environment_names : {
        "${env_name}-${local.plan_key}"  = local.resource_names_per_environment[env_name].user_assigned_managed_identity_plan
        "${env_name}-${local.apply_key}" = local.resource_names_per_environment[env_name].user_assigned_managed_identity_apply
      }
  ]...)

  # Federated credentials - maps managed identity keys to their OIDC subjects/issuers
  federated_credentials = length(local.effective_environment_names) == 1 ? {
    # Single environment - use existing module.github output structure
    for key, value in module.github.subjects :
    key => {
      user_assigned_managed_identity_key = value.user_assigned_managed_identity_key
      federated_credential_subject       = value.subject
      federated_credential_issuer        = module.github.issuer
      federated_credential_name          = "${local.resource_names_per_environment[local.primary_environment_name].user_assigned_managed_identity_federated_credentials_prefix}-${key}"
    }
  } : merge([
    # Multi-environment - use prefixed keys matching the github module output
    for key, value in module.github.subjects : {
      (key) = {
        user_assigned_managed_identity_key = value.user_assigned_managed_identity_key
        federated_credential_subject       = value.subject
        federated_credential_issuer        = module.github.issuer
        # Extract env_name from the subject key (format: "env_name-workflow_key-identity_key")
        federated_credential_name          = "${local.resource_names_per_environment[split("-", key)[0]].user_assigned_managed_identity_federated_credentials_prefix}-${key}"
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
