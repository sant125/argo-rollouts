# Lido por toda unit. Cliente, ambiente e região vêm dos .hcl nas pastas acima.
locals {
  client = read_terragrunt_config(find_in_parent_folders("client.hcl")).locals
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  region = read_terragrunt_config(find_in_parent_folders("region.hcl")).locals
  name   = "${local.client.name}-${local.env.name}"
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket       = "${local.client.name}-tfstate-${local.client.account_id}"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = local.client.state_region
    profile      = local.client.aws_profile
    encrypt      = true
    use_lockfile = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOT
provider "aws" {
  region  = "${local.region.name}"
  profile = "${local.client.aws_profile}"
  default_tags {
    tags = {
      Cliente    = "${local.client.name}"
      Ambiente   = "${local.env.name}"
      Gerenciado = "terragrunt"
    }
  }
}
EOT
}
