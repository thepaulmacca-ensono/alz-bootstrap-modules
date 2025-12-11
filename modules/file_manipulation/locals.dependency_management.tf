locals {
  # Renovate configuration for Azure DevOps
  # https://docs.renovatebot.com/configuration-options/
  renovate_config_json = <<-JSON
    {
      // See: https://docs.renovatebot.com/configuration-options/
      "$schema": "https://docs.renovatebot.com/renovate-schema.json",

      // Use recommended defaults as base configuration
      "extends": ["config:recommended"],

      // Ignore Terraform version updates - these require manual review
      // to ensure compatibility with providers and modules
      "ignoreDeps": ["hashicorp/terraform"],

      // Label pull requests for easier filtering
      "labels": ["dependencies"],

      "packageRules": [
        {
          // Group minor and patch updates for Terraform providers and modules
          // to reduce PR noise while maintaining security updates
          "groupName": "terraform minor and patch updates",
          "matchManagers": ["terraform", "tflint-plugin"],
          "matchUpdateTypes": ["minor", "patch"],
          "autoMerge": true
        }
      ]
    }
  JSON

  # Renovate pipeline YAML for Azure DevOps
  # Requires RENOVATE_TOKEN secret variable to be set in the pipeline (PAT with Code Read & Write permissions)
  # Also requires a GITHUB_TOKEN secret variable for fetching release notes from GitHub (PAT with Public repositories scope)
  renovate_pipeline_yaml = <<-YAML
    trigger: none

    schedules:
      - cron: "0 3 * * 0"
        displayName: "Weekly Renovate Run"
        branches:
          include:
            - main
        always: true

    pool:
      vmImage: "ubuntu-latest"

    steps:
      - task: UseNode@1
        displayName: "Install Node.js"
        inputs:
          version: "20.x"

      - script: |
          npx renovate
        displayName: "Run Renovate"
        env:
          RENOVATE_PLATFORM: azure
          RENOVATE_ENDPOINT: $(System.CollectionUri)
          RENOVATE_TOKEN: $(RENOVATE_TOKEN)
          RENOVATE_REPOSITORIES: $(System.TeamProject)/$(Build.Repository.Name)
          GITHUB_COM_TOKEN: $(GITHUB_TOKEN)
          LOG_LEVEL: info
  YAML

  renovate_files = var.enable_renovate && local.is_azuredevops ? {
    "renovate.json5" = {
      content = local.renovate_config_json
    }
    "${var.pipeline_target_folder_name}/renovate.yaml" = {
      content = local.renovate_pipeline_yaml
    }
  } : {}

  # Dependabot configuration for GitHub
  # https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file
  dependabot_config = yamlencode({
    version = 2
    updates = [
      {
        package-ecosystem = "terraform"
        directory         = "/"
        schedule = {
          interval = "weekly"
        }
        labels                   = ["dependencies"]
        open-pull-requests-limit = 10
      }
    ]
  })

  dependabot_file = var.enable_dependabot && local.is_github ? {
    ".github/dependabot.yml" = {
      content = local.dependabot_config
    }
  } : {}

  # Combined dependency management files
  dependency_management_files = merge(local.renovate_files, local.dependabot_file)
}
