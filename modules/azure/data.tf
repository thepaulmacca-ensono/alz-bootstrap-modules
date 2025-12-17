data "azurerm_subscription" "alz" {
  for_each        = local.subscription_ids
  subscription_id = each.key
}

data "azurerm_management_group" "alz" {
  name = var.root_parent_management_group_id
}

data "http" "ip" {
  count = var.use_private_networking && var.use_self_hosted_agents && var.allow_storage_access_from_my_ip ? 1 : 0
  url   = "https://api.ipify.org/"
  retry {
    attempts     = 5
    max_delay_ms = 1000
    min_delay_ms = 500
  }
}

module "regions" {
  source          = "Azure/avm-utl-regions/azurerm"
  version         = "0.9.2"
  use_cached_data = false
}

locals {
  regions = { for region in module.regions.regions_by_name : region.name => {
    display_name       = region.display_name
    paired_region_name = region.paired_region_name
    zones              = region.zones == null ? [] : region.zones
    }
  }
  bootstrap_location_zones       = local.regions[var.azure_location].zones
  bootstrap_location_paired_name = local.regions[var.azure_location].paired_region_name

  # Auto-select optimal storage replication type per region based on zone availability
  # ZRS requires 3+ availability zones, fallback to GRS for geo-redundancy otherwise
  storage_replication_type = {
    for region_key, config in var.storage_accounts : region_key =>
    length(local.regions[lookup(config, "location", var.azure_location)].zones) >= 3 ? "ZRS" : "GRS"
  }
}
