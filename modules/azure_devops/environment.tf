resource "azuredevops_environment" "alz" {
  for_each   = local.all_environments
  name       = each.value.environment_name
  project_id = local.project_id
}
