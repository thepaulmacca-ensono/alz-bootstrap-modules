resource "github_repository" "alz" {
  for_each             = local.effective_repositories
  name                 = each.value.repository_name
  description          = each.value.repository_name
  auto_init            = true
  visibility           = data.github_organization.alz.plan == local.free_plan ? "public" : "private"
  allow_update_branch  = true
  allow_merge_commit   = false
  allow_rebase_merge   = false
  vulnerability_alerts = true
}

resource "github_repository_file" "alz" {
  for_each            = local.all_repository_files
  repository          = github_repository.alz[each.value.repo_key].name
  file                = each.value.path
  content             = each.value.content
  commit_author       = local.default_commit_email
  commit_email        = local.default_commit_email
  commit_message      = "Add ${each.value.path} [skip ci]"
  overwrite_on_create = true
}

resource "github_branch_protection" "alz" {
  for_each                        = var.create_branch_policies ? local.effective_repositories : {}
  depends_on                      = [github_repository_file.alz]
  repository_id                   = github_repository.alz[each.key].name
  pattern                         = "main"
  enforce_admins                  = true
  required_linear_history         = true
  require_conversation_resolution = true

  required_pull_request_reviews {
    dismiss_stale_reviews           = true
    restrict_dismissals             = true
    required_approving_review_count = local.approver_count > 1 ? 1 : 0
  }
}
