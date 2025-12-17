locals {
  is_github                             = var.vcs_type == "github"
  is_azuredevops                        = var.vcs_type == "azuredevops"
  use_separate_repository_for_templates = coalesce(var.use_separate_repository_for_templates, false)
  repository_name_templates             = local.use_separate_repository_for_templates ? var.resource_names.version_control_system_repository_templates : try(var.resource_names.version_control_system_repository, "")

  pipeline_files          = var.pipeline_files_directory_path == null ? [] : fileset(var.pipeline_files_directory_path, "**/*.*")
  pipeline_template_files = var.pipeline_template_files_directory_path == null ? [] : fileset(var.pipeline_template_files_directory_path, "**/*.*")

  templated_files = {
    main_files = {
      source_directory_path = var.pipeline_files_directory_path
      files                 = local.pipeline_files
    }
    template_files = {
      source_directory_path = var.pipeline_template_files_directory_path
      files                 = local.pipeline_template_files
    }
  }

  # Compute multi-region settings
  multi_region_enabled = length(var.regions) > 1
  primary_region       = try([for r in var.regions : r if r.is_primary][0], try(var.regions[0], null))

  templated_files_final = { for key, value in local.templated_files : key => {
    for pipeline_file in value.files : "${var.pipeline_target_folder_name}/${pipeline_file}" => {
      content = templatefile("${value.source_directory_path}/${pipeline_file}", {
        agent_pool_or_runner_configuration = var.agent_pool_or_runner_configuration
        environment_name_plan              = try(var.resource_names.version_control_system_environment_plan, "")
        environment_name_apply             = try(var.resource_names.version_control_system_environment_apply, "")
        variable_group_name                = local.is_azuredevops ? var.resource_names.version_control_system_variable_group : ""
        project_or_organization_name       = var.project_or_organization_name
        repository_name_templates          = local.repository_name_templates
        service_connection_name_plan       = local.is_azuredevops ? var.resource_names.version_control_system_service_connection_plan : ""
        service_connection_name_apply      = local.is_azuredevops ? var.resource_names.version_control_system_service_connection_apply : ""
        self_hosted_agent                  = var.use_self_hosted_agents_runners
        concurrency_value                  = var.concurrency_value
        ci_template_path                   = "${var.pipeline_target_folder_name}/${coalesce(var.ci_template_file_name, "empty")}"
        cd_template_path                   = "${var.pipeline_target_folder_name}/${coalesce(var.cd_template_file_name, "empty")}"
        root_module_folder_relative_path   = var.root_module_folder_relative_path
        # Multi-region support
        regions              = var.regions
        multi_region_enabled = local.multi_region_enabled
        primary_region       = local.primary_region
    }) }
    }
  }
}

locals {
  # Build a map of module files and turn on the terraform backend block
  module_files = { for key, value in var.files : key =>
    {
      content = try(replace((file(value.path)), "# backend \"azurerm\" {}", "backend \"azurerm\" {}"), "unsupported_file_type")
    }
  }

  # Build a map of module files with types that are supported
  module_files_supported = { for key, value in local.module_files : key => value if value.content != "unsupported_file_type" && !endswith(key, "-cache.json") }

  # Create final maps of all files to be included in the repositories
  repository_files          = merge(local.templated_files_final.main_files, local.module_files_supported, local.use_separate_repository_for_templates ? {} : local.templated_files_final.template_files, local.dependency_management_files, local.pull_request_template_files)
  template_repository_files = local.use_separate_repository_for_templates ? local.templated_files_final.template_files : {}
}
