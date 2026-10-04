include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "tfr:///terraform-aws-modules/vpc/aws?version=6.7.3"
}

inputs = {
  name = include.root.locals.name
  cidr = include.root.locals.env.vpc_cidr
  azs  = include.root.locals.region.azs

  # /19 pros nós,pods e ALB, /27 pras ENIs do control plane
  public_subnets = [for i in range(3) : cidrsubnet(include.root.locals.env.vpc_cidr, 3, i)]
  intra_subnets  = [for i in range(3) : cidrsubnet(include.root.locals.env.vpc_cidr, 11, 832 + i)]

  enable_nat_gateway = false

  # associar ip pub nas ec2 nas subnets pubs, modulo tem default false
  map_public_ip_on_launch = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
    "karpenter.sh/discovery" = include.root.locals.name
  }
}
