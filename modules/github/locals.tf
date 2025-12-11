locals {
  apply_key = "apply"
}

locals {
  free_plan       = "free"
  enterprise_plan = "enterprise"
}

locals {
  use_runner_group = var.use_runner_group && data.github_organization.alz.plan == local.enterprise_plan && var.use_self_hosted_runners
}

locals {
  primary_approver     = length(var.approvers) > 0 ? var.approvers[0] : ""
  default_commit_email = coalesce(local.primary_approver, "demo@microsoft.com")
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
      workflows                   = var.workflows
      managed_identity_client_ids = var.managed_identity_client_ids
      storage_container_name      = var.backend_azure_storage_account_container_name
    }
  }

  # Flatten environments across all repositories for resource creation
  # Keys are formatted as "repo_key-env_key" (e.g., "mgmt-plan", "connectivity-apply")
  all_environments = merge([
    for repo_key, repo in local.effective_repositories : {
      for env_key, env_name in repo.environments :
      "${repo_key}-${env_key}" => {
        repo_key         = repo_key
        env_key          = env_key
        environment_name = env_name
        repository_name  = repo.repository_name
      }
    }
  ]...)

  # Flatten repository files across all repositories for resource creation
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

locals {
  repository_name_templates = var.use_template_repository ? var.repository_name_templates : (var.repositories != null ? values(var.repositories)[0].repository_name : var.repository_name)
  template_claim_structure  = "${var.organization_name}/${local.repository_name_templates}/%s@refs/heads/main"

  # OIDC subjects for all repositories
  oidc_subjects_flattened = flatten([
    for repo_key, repo in local.effective_repositories : [
      for workflow_key, workflow in repo.workflows : [
        for mapping in workflow.environment_user_assigned_managed_identity_mappings :
        {
          subject_key                        = "${repo_key}-${workflow_key}-${mapping.user_assigned_managed_identity_key}"
          repo_key                           = repo_key
          user_assigned_managed_identity_key = local.use_multi_repository_mode ? "${repo_key}-${mapping.user_assigned_managed_identity_key}" : mapping.user_assigned_managed_identity_key
          subject                            = "repo:${var.organization_name}/${repo.repository_name}:environment:${repo.environments[mapping.environment_key]}:job_workflow_ref:${format(local.template_claim_structure, workflow.workflow_file_name)}"
        }
      ]
    ]
  ])

  oidc_subjects = { for oidc_subject in local.oidc_subjects_flattened : oidc_subject.subject_key => {
    user_assigned_managed_identity_key = oidc_subject.user_assigned_managed_identity_key
    subject                            = oidc_subject.subject
  } }
}

locals {
  runner_group_name = local.use_runner_group ? github_actions_runner_group.alz[0].name : var.default_runner_group_name
}
