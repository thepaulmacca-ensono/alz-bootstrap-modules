variable "use_legacy_organization_url" {
  description = <<-EOT
    **(Required)** Whether to use the legacy Azure DevOps organization URL format.

    Set to true for <organization>.visualstudio.com format (legacy).
    Set to false for dev.azure.com/<organization> format (modern).
    Required for older organizations that haven't migrated to the new URL structure.
  EOT
  type        = bool
}

variable "organization_name" {
  description = <<-EOT
    **(Required)** Name of the Azure DevOps organization where resources will be created.

    This is the organization segment in the URL.
    Example: 'my-org' from dev.azure.com/my-org
  EOT
  type        = string
}

variable "create_project" {
  description = <<-EOT
    **(Required)** Whether to create a new Azure DevOps project.

    Set to true to create a new project with the specified name.
    Set to false to use an existing project.
  EOT
  type        = bool
}

variable "project_name" {
  description = <<-EOT
    **(Required)** Name of the Azure DevOps project for Azure Landing Zones deployment.

    This project will contain repositories, pipelines, and other deployment resources.
    Used for both new and existing projects depending on create_project setting.
  EOT
  type        = string
}

variable "repositories" {
  description = <<-EOT
    **(Required)** Map of repositories to create for multi-environment deployments.

    Each repository entry includes its own environments, pipelines, and service connections.

    Map configuration where:
    - **Key**: Repository identifier (e.g., environment name like 'management', 'connectivity')
    - **Value**: Object containing:
      - `repository_name` (string) - Name of the repository
      - `repository_files` (map) - Files to create in the repository
      - `environments` (map) - Environments configuration for this repository
      - `pipelines` (map) - Pipelines configuration for this repository
      - `managed_identity_client_ids` (map) - Managed identity client IDs for service connections
      - `storage_container_name` (string) - Storage container name for this environment
  EOT
  type = map(object({
    repository_name = string
    repository_files = map(object({
      content = string
    }))
    environments = map(object({
      environment_name                      = string
      service_connection_name               = string
      service_connection_required_templates = list(string)
    }))
    pipelines = map(object({
      pipeline_name           = string
      pipeline_file_name      = string
      environment_keys        = list(string)
      service_connection_keys = list(string)
    }))
    managed_identity_client_ids = map(string)
    storage_container_name      = string
  }))
}

variable "template_repository_files" {
  description = <<-EOT
    **(Required)** Map of files to create in the separate templates repository (if used).

    Contains reusable pipeline templates that can be referenced from the main repository,
    providing an additional security boundary for pipeline definitions.

    Map configuration where:
    - **Key**: File path relative to repository root
    - **Value**: Object containing:
      - `content` (string) - File contents
  EOT
  type = map(object({
    content = string
  }))
}



variable "azure_tenant_id" {
  description = <<-EOT
    **(Required)** Azure Active Directory (Entra ID) tenant ID where Azure Landing Zones will be deployed.

    Used for configuring service connections and authentication.
    Must be a valid GUID format.
  EOT
  type        = string
}

variable "azure_subscription_id" {
  description = <<-EOT
    **(Required)** Azure subscription ID for the bootstrap resources.

    This subscription hosts the CI/CD infrastructure including storage account and managed identities.
    Referenced in pipeline variables and must be a valid GUID format.
  EOT
  type        = string
}

variable "azure_subscription_name" {
  description = <<-EOT
    **(Required)** Human-readable name of the Azure subscription containing bootstrap resources.

    Used in service connection configuration and for pipeline variable documentation.
  EOT
  type        = string
}







variable "variable_groups" {
  description = <<-EOT
    **(Required)** Map of per-landing-zone-per-region variable groups.

    Creates one variable group per landing zone per region, each containing the backend storage
    configuration for that landing zone and region's Terraform state.

    Map configuration where:
    - **Key**: Landing zone and region key (e.g., "management-uksouth", "connectivity-ukwest")
    - **Value**: Object containing:
      - `variable_group_name` (string) - Name of the variable group
      - `resource_group_name` (string) - Backend state resource group name
      - `storage_account_name` (string) - Backend state storage account name
      - `container_name` (string) - Backend state container name
      - `landing_zone` (optional string) - Landing zone this variable group belongs to
      - `region` (optional string) - Region this variable group belongs to
  EOT
  type = map(object({
    variable_group_name  = string
    resource_group_name  = string
    storage_account_name = string
    container_name       = string
    landing_zone         = optional(string)
    region               = optional(string)
  }))
}

variable "approvers" {
  description = <<-EOT
    **(Required)** List of Azure DevOps user principal names (emails) authorized to approve deployments.

    These users must approve before pipeline stages targeting protected environments can execute.

    Example:
    ```
    [
      "user1@contoso.com",
      "user2@contoso.com"
    ]
    ```
  EOT
  type        = list(string)
}

variable "group_name" {
  description = <<-EOT
    **(Required)** Name of the Azure DevOps group to create for approvers.

    This group is configured as the approver for protected environments,
    providing centralized approval management.
  EOT
  type        = string
}

variable "use_template_repository" {
  description = <<-EOT
    **(Required)** Whether to create a separate repository for pipeline templates.

    When true, creates an additional repository for reusable pipeline templates,
    enhancing security by separating pipeline logic from deployment code.
  EOT
  type        = bool
}

variable "repository_name_templates" {
  description = <<-EOT
    **(Required)** Name of the separate repository for pipeline templates.

    Used only when use_template_repository is true.
    This repository contains reusable YAML templates referenced by pipelines in the main repository.
  EOT
  type        = string
}

variable "agent_pool_name" {
  description = <<-EOT
    **(Required)** Name of the Azure DevOps agent pool for running pipeline jobs.

    When using self-hosted agents, this pool must contain registered agents with appropriate capabilities.
    For Microsoft-hosted agents, use 'Azure Pipelines'.
  EOT
  type        = string
}

variable "use_self_hosted_agents" {
  description = <<-EOT
    **(Required)** Whether pipelines use self-hosted agents or Microsoft-hosted agents.

    When true, requires an agent pool with registered self-hosted agents (e.g., Azure Container Instances).
    When false, uses Microsoft-hosted agents from Azure Pipelines.
  EOT
  type        = bool
}

variable "create_branch_policies" {
  description = <<-EOT
    **(Required)** Whether to create branch protection policies on the main branch.

    When enabled, enforces code review requirements, build validation,
    and other quality gates before merging changes.
  EOT
  type        = bool
}
