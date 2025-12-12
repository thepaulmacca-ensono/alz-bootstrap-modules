locals {
  organization_url = startswith(lower(var.organization_name), "https://") || startswith(lower(var.organization_name), "http://") ? var.organization_name : (var.use_legacy_organization_url ? "https://${var.organization_name}.visualstudio.com" : "https://dev.azure.com/${var.organization_name}")
}

locals {
  apply_key = "apply"
}

locals {
  authentication_scheme_workload_identity_federation = "WorkloadIdentityFederation"
}

locals {
  default_branch = "refs/heads/main"
}

locals {
  repository_name_templates = var.use_template_repository ? var.repository_name_templates : values(var.repositories)[0].repository_name
}

# Multi-repository mode (all environments have their own repository config)
locals {
  # Flatten environments across all repositories for resource creation
  # Keys are formatted as "repo_key-env_key" (e.g., "mgmt-plan", "connectivity-apply")
  all_environments = merge([
    for repo_key, repo in var.repositories : {
      for env_key, env in repo.environments :
      "${repo_key}-${env_key}" => merge(env, {
        repo_key                   = repo_key
        env_key                    = env_key
        managed_identity_client_id = repo.managed_identity_client_ids[env_key]
        repository_name            = repo.repository_name
      })
    }
  ]...)

  # Filter for apply environments (for approval checks)
  apply_environments = {
    for key, env in local.all_environments :
    key => env if env.env_key == local.apply_key
  }

  # Flatten repository files across all repositories for resource creation
  # Keys are formatted as "repo_key/file_path" (e.g., "mgmt/main.tf")
  all_repository_files = merge([
    for repo_key, repo in var.repositories : {
      for file_path, file in repo.repository_files :
      "${repo_key}/${file_path}" => {
        repo_key = repo_key
        path     = file_path
        content  = file.content
      }
    }
  ]...)
}
