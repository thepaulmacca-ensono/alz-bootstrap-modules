locals {
  # Pull request template content
  pull_request_template_content = <<-MARKDOWN
    [XXXX-<Title> - Please use the Work Item number and Title as PR Name, not subtasks]

    #### 📲 What

    A description of the change.

    #### 🤔 Why

    Why it's needed, background context.

    #### 🛠 How

    More in-depth discussion of the change or implementation.

    #### 👀 Evidence

    Screenshots / external resources / links / etc.
    Link to documentation updated with changes impacted in the PR

    #### 🕵️ How to test

    Notes for QA

    #### ✅ Acceptance criteria Checklist

    - [ ] Code peer reviewed?
    - [ ] Documentation has been updated to reflect the changes?
    - [ ] Passing all automated tests, including a successful deployment?
    - [ ] Passing any exploratory testing?
    - [ ] Rebased/merged with latest changes from development and re-tested?
    - [ ] Meeting the Coding Standards?
  MARKDOWN

  # Pull request template file for Azure DevOps
  pull_request_template_azuredevops = local.is_azuredevops ? {
    ".azuredevops/pull_request_template.md" = {
      content = local.pull_request_template_content
    }
  } : {}

  # Pull request template file for GitHub
  pull_request_template_github = local.is_github ? {
    ".github/pull_request_template.md" = {
      content = local.pull_request_template_content
    }
  } : {}

  # Combined pull request template files
  pull_request_template_files = merge(local.pull_request_template_azuredevops, local.pull_request_template_github)
}
