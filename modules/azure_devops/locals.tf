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
  repository_name_templates = var.use_template_repository ? var.repository_name_templates : (var.repositories != null ? values(var.repositories)[0].repository_name : var.repository_name)
}

# Multi-repository mode detection
locals {
  use_multi_repository_mode = var.repositories != null

  # In single-repository mode, create a synthetic repositories map for unified processing
  effective_repositories = local.use_multi_repository_mode ? var.repositories : {
    default = {
      repository_name             = var.repository_name
      repository_files            = var.repository_files
      environments                = var.environments
      pipelines                   = var.pipelines
      managed_identity_client_ids = var.managed_identity_client_ids
      storage_container_name      = var.backend_azure_storage_account_container_name
    }
  }

  # Flatten environments across all repositories for resource creation
  # Keys are formatted as "repo_key-env_key" (e.g., "mgmt-plan", "connectivity-apply")
  all_environments = merge([
    for repo_key, repo in local.effective_repositories : {
      for env_key, env in repo.environments :
      "${repo_key}-${env_key}" => merge(env, {
        repo_key                    = repo_key
        env_key                     = env_key
        managed_identity_client_id  = repo.managed_identity_client_ids[env_key]
        repository_name             = repo.repository_name
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
    for repo_key, repo in local.effective_repositories : {
      for file_path, file in repo.repository_files :
      "${repo_key}/${file_path}" => {
        repo_key = repo_key
        path     = file_path
        content  = file.content
      }
    }
  ]...)
}
