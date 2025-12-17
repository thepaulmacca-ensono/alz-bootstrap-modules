# Accelerator Bootstrap Modules

[![End to End Tests](https://github.com/Azure/accelerator-bootstrap-modules/actions/workflows/end-to-end-test.yml/badge.svg)](https://github.com/Azure/accelerator-bootstrap-modules/actions/workflows/end-to-end-test.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/Azure/accelerator-bootstrap-modules/badge)](https://scorecard.dev/viewer/?uri=github.com/Azure/accelerator-bootstrap-modules)

This repository contains the Terraform modules that are used to deploy the accelerator bootstrap environments for Azure Landing Zones.

## Supported Infrastructure as Code (IaC) Types

This bootstrap framework supports Terraform-based Azure Landing Zones:

| IaC Type | Description | Repository |
|----------|-------------|------------|
| **terraform** | Terraform-based Azure Landing Zones | [alz-terraform-accelerator](https://github.com/Azure/alz-terraform-accelerator) |

## Configuration

The supported frameworks and their configuration are defined in [`.config/ALZ-Powershell.config.json`](.config/ALZ-Powershell.config.json).
