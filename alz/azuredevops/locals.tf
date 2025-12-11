# Environment Names Setup
# Compute effective environment names - use environment_names if set, otherwise fallback to single environment_name
# Note: We use a predefined order to ensure 'mgmt' is always first (for shared resources naming)
locals {
  # Canonical order for environments - mgmt should always be first for shared resource naming
  canonical_environment_order = ["mgmt", "conn", "id", "sec"]

  # Map short environment keys to long display names for VCS resources
  environment_long_names = {
    mgmt = "management"
    conn = "connectivity"
    id   = "identity"
    sec  = "security"
  }

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
  iac_terraform = "terraform"
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
  pipeline_files_directory_path          = "${path.module}/pipelines/${var.iac_type}/main"
  pipeline_template_files_directory_path = "${path.module}/pipelines/${var.iac_type}/templates"
}

locals {
  target_subscriptions_legacy = distinct([var.subscription_id_connectivity, var.subscription_id_identity, var.subscription_id_management])
  target_subscriptions        = length(var.subscription_ids) > 0 ? distinct(values(var.subscription_ids)) : local.target_subscriptions_legacy
}

# Managed identities - keys are prefixed with environment: "mgmt-plan", "conn-apply", etc.
# Each identity includes name and resource_group_key to support per-environment resource groups
locals {
  managed_identities = merge([
    for env_name in local.effective_environment_names : {
      "${env_name}-${local.plan_key}" = {
        name               = local.resource_names_per_environment[env_name].user_assigned_managed_identity_plan
        resource_group_key = env_name
      }
      "${env_name}-${local.apply_key}" = {
        name               = local.resource_names_per_environment[env_name].user_assigned_managed_identity_apply
        resource_group_key = env_name
      }
    }
  ]...)

  # Per-environment identity resource groups
  resource_group_identity_names = {
    for env_name in local.effective_environment_names :
    env_name => local.resource_names_per_environment[env_name].resource_group_identity
  }

  # Per-environment storage accounts
  storage_accounts = {
    for env_name in local.effective_environment_names :
    env_name => {
      resource_group_name  = local.resource_names_per_environment[env_name].resource_group_state
      storage_account_name = local.resource_names_per_environment[env_name].storage_account
      container_name       = local.resource_names_per_environment[env_name].storage_container
    }
  }

  # Per-environment variable groups
  variable_groups = {
    for env_name in local.effective_environment_names :
    env_name => {
      variable_group_name  = local.resource_names_per_environment[env_name].version_control_system_variable_group
      resource_group_name  = local.resource_names_per_environment[env_name].resource_group_state
      storage_account_name = local.resource_names_per_environment[env_name].storage_account
      container_name       = local.resource_names_per_environment[env_name].storage_container
    }
  }

  # Federated credentials - maps managed identity keys to their OIDC subjects/issuers
  federated_credentials = merge([
    for env_name in local.effective_environment_names : {
      "${env_name}-${local.plan_key}" = {
        user_assigned_managed_identity_key = "${env_name}-${local.plan_key}"
        federated_credential_subject       = module.azure_devops.subjects["${env_name}-${local.plan_key}"]
        federated_credential_issuer        = module.azure_devops.issuers["${env_name}-${local.plan_key}"]
        federated_credential_name          = local.resource_names_per_environment[env_name].user_assigned_managed_identity_federated_credentials_plan
      }
      "${env_name}-${local.apply_key}" = {
        user_assigned_managed_identity_key = "${env_name}-${local.apply_key}"
        federated_credential_subject       = module.azure_devops.subjects["${env_name}-${local.apply_key}"]
        federated_credential_issuer        = module.azure_devops.issuers["${env_name}-${local.apply_key}"]
        federated_credential_name          = local.resource_names_per_environment[env_name].user_assigned_managed_identity_federated_credentials_apply
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

# Per-environment Azure DevOps environments configuration
locals {
  environments_per_environment = {
    for env_name in local.effective_environment_names : env_name => {
      (local.plan_key) = {
        environment_name        = local.resource_names_per_environment[env_name].version_control_system_environment_plan
        service_connection_name = local.resource_names_per_environment[env_name].version_control_system_service_connection_plan
        service_connection_required_templates = [
          "${local.target_folder_name}/${local.ci_template_file_name}",
          "${local.target_folder_name}/${local.cd_template_file_name}"
        ]
      }
      (local.apply_key) = {
        environment_name        = local.resource_names_per_environment[env_name].version_control_system_environment_apply
        service_connection_name = local.resource_names_per_environment[env_name].version_control_system_service_connection_apply
        service_connection_required_templates = [
          "${local.target_folder_name}/${local.cd_template_file_name}"
        ]
      }
    }
  }

  # Per-environment pipelines configuration
  pipelines_per_environment = {
    for env_name in local.effective_environment_names : env_name => merge(
      {
        ci = {
          pipeline_name      = local.resource_names_per_environment[env_name].version_control_system_pipeline_name_ci
          pipeline_file_name = "${local.target_folder_name}/${local.ci_file_name}"
          environment_keys = [
            local.plan_key
          ]
          service_connection_keys = [
            local.plan_key
          ]
        }
        cd = {
          pipeline_name      = local.resource_names_per_environment[env_name].version_control_system_pipeline_name_cd
          pipeline_file_name = "${local.target_folder_name}/${local.cd_file_name}"
          environment_keys = [
            local.plan_key,
            local.apply_key
          ]
          service_connection_keys = [
            local.plan_key,
            local.apply_key
          ]
        }
      },
      var.enable_renovate ? {
        renovate = {
          pipeline_name           = local.resource_names_per_environment[env_name].version_control_system_pipeline_name_renovate
          pipeline_file_name      = "${local.target_folder_name}/${local.renovate_file_name}"
          environment_keys        = []
          service_connection_keys = []
        }
      } : {}
    )
  }

  # Per-environment managed identity client IDs map (keyed by plan/apply)
  managed_identity_client_ids_per_environment = {
    for env_name in local.effective_environment_names : env_name => {
      (local.plan_key)  = module.azure.user_assigned_managed_identity_client_ids["${env_name}-${local.plan_key}"]
      (local.apply_key) = module.azure.user_assigned_managed_identity_client_ids["${env_name}-${local.apply_key}"]
    }
  }

  # Multi-environment repositories map for azure_devops module
  repositories = {
    for env_name in local.effective_environment_names : env_name => {
      repository_name             = local.resource_names_per_environment[env_name].version_control_system_repository
      repository_files            = module.file_manipulation.repository_files # TODO: Per-environment files
      environments                = local.environments_per_environment[env_name]
      pipelines                   = local.pipelines_per_environment[env_name]
      managed_identity_client_ids = local.managed_identity_client_ids_per_environment[env_name]
      storage_container_name      = local.resource_names_per_environment[env_name].storage_container
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

# Role assignments expansion - identity keys are prefixed: "mgmt-plan", "conn-apply", etc.
# This local expands the base role assignments to cover all environment identities
locals {
  role_assignments_terraform_expanded = merge([
    for env_name in local.effective_environment_names : {
      for key, value in var.role_assignments_terraform :
      "${env_name}-${key}" => {
        custom_role_definition_key         = value.custom_role_definition_key
        user_assigned_managed_identity_key = "${env_name}-${value.user_assigned_managed_identity_key}"
        scope                              = value.scope
      }
    }
  ]...)

  role_assignments_bicep_expanded = merge([
    for env_name in local.effective_environment_names : {
      for key, value in var.role_assignments_bicep :
      "${env_name}-${key}" => {
        custom_role_definition_key         = value.custom_role_definition_key
        user_assigned_managed_identity_key = "${env_name}-${value.user_assigned_managed_identity_key}"
        scope                              = value.scope
      }
    }
  ]...)

  role_assignments_effective = var.iac_type == "terraform" ? local.role_assignments_terraform_expanded : local.role_assignments_bicep_expanded
}
