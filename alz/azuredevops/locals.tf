# Environment Names Setup
# Compute effective environment names - use environment_names if set, otherwise fallback to single environment_name
locals {
  effective_environment_names = var.environment_names != null ? keys(var.environment_names) : [var.environment_name]

  # Primary environment is the first one (used for shared resources naming)
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
    # Single environment - use simple keys for backwards compatibility
    (local.plan_key) = {
      user_assigned_managed_identity_key = local.plan_key
      federated_credential_subject       = module.azure_devops.subjects[local.plan_key]
      federated_credential_issuer        = module.azure_devops.issuers[local.plan_key]
      federated_credential_name          = local.resource_names_per_environment[local.primary_environment_name].user_assigned_managed_identity_federated_credentials_plan
    }
    (local.apply_key) = {
      user_assigned_managed_identity_key = local.apply_key
      federated_credential_subject       = module.azure_devops.subjects[local.apply_key]
      federated_credential_issuer        = module.azure_devops.issuers[local.apply_key]
      federated_credential_name          = local.resource_names_per_environment[local.primary_environment_name].user_assigned_managed_identity_federated_credentials_apply
    }
  } : merge([
    # Multi-environment - use prefixed keys matching the azure_devops module output
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

  # Legacy single-environment format (for backwards compatibility during transition)
  environments = local.environments_per_environment[local.primary_environment_name]

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
      (local.plan_key)  = module.azure.user_assigned_managed_identity_client_ids[length(local.effective_environment_names) == 1 ? local.plan_key : "${env_name}-${local.plan_key}"]
      (local.apply_key) = module.azure.user_assigned_managed_identity_client_ids[length(local.effective_environment_names) == 1 ? local.apply_key : "${env_name}-${local.apply_key}"]
    }
  }

  # Multi-environment repositories map for azure_devops module
  # Used when environment_names contains more than one environment
  repositories = length(local.effective_environment_names) == 1 ? null : {
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
