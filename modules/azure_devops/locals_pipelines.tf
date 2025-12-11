locals {
  # Map short environment keys to long display names for pipeline folders
  environment_long_names = {
    mgmt = "management"
    conn = "connectivity"
    id   = "identity"
    sec  = "security"
  }

  # Flatten pipelines across all repositories
  # Keys are formatted as "repo_key-pipeline_key" (e.g., "mgmt-ci", "connectivity-cd")
  all_pipelines = merge([
    for repo_key, repo in local.effective_repositories : {
      for pipeline_key, pipeline in repo.pipelines :
      "${repo_key}-${pipeline_key}" => {
        repo_key      = repo_key
        pipeline_key  = pipeline_key
        pipeline_name = pipeline.pipeline_name
        # In multi-repo mode, organize pipelines into folders by environment (using long names)
        pipeline_folder = local.use_multi_repository_mode ? "\\${lookup(local.environment_long_names, repo_key, repo_key)}" : null
        # Reference the file in the correct repository
        file = azuredevops_git_repository_file.alz["${repo_key}/${pipeline.pipeline_file_name}"].file
        # Environment keys need to be prefixed with repo_key to match all_environments
        environments = [for environment_key in pipeline.environment_keys :
          {
            environment_key          = environment_key
            full_environment_key     = "${repo_key}-${environment_key}"
            environment_id           = azuredevops_environment.alz["${repo_key}-${environment_key}"].id
          }
        ]
        # Service connection keys need to be prefixed with repo_key to match all_environments
        service_connections = [for service_connection_key in pipeline.service_connection_keys :
          {
            service_connection_key      = service_connection_key
            full_service_connection_key = "${repo_key}-${service_connection_key}"
            service_connection_id       = azuredevops_serviceendpoint_azurerm.alz["${repo_key}-${service_connection_key}"].id
          }
        ]
        repository_id = azuredevops_git_repository.alz[repo_key].id
      }
    }
  ]...)

  # Legacy local for backwards compatibility (used by pipeline.tf)
  pipelines = local.all_pipelines

  pipeline_environments = flatten([for pipeline_key, pipeline in local.all_pipelines :
    [for environment in pipeline.environments : {
      pipeline_key         = pipeline_key
      environment_key      = environment.environment_key
      full_environment_key = environment.full_environment_key
      pipeline_id          = azuredevops_build_definition.alz[pipeline_key].id
      environment_id       = environment.environment_id
      }
    ]
  ])

  pipeline_service_connections = flatten([for pipeline_key, pipeline in local.all_pipelines :
    [for service_connection in pipeline.service_connections : {
      pipeline_key                = pipeline_key
      service_connection_key      = service_connection.service_connection_key
      full_service_connection_key = service_connection.full_service_connection_key
      pipeline_id                 = azuredevops_build_definition.alz[pipeline_key].id
      service_connection_id       = service_connection.service_connection_id
      }
    ]
  ])

  pipeline_environments_map = { for pipeline_environment in local.pipeline_environments : "${pipeline_environment.pipeline_key}-${pipeline_environment.environment_key}" => {
    pipeline_id    = pipeline_environment.pipeline_id
    environment_id = pipeline_environment.environment_id
    }
  }

  pipeline_service_connections_map = { for pipeline_service_connection in local.pipeline_service_connections : "${pipeline_service_connection.pipeline_key}-${pipeline_service_connection.service_connection_key}" => {
    pipeline_id           = pipeline_service_connection.pipeline_id
    service_connection_id = pipeline_service_connection.service_connection_id
    }
  }
}
