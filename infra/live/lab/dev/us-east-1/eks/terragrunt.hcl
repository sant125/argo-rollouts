include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "tfr:///terraform-aws-modules/eks/aws?version=21.26.0"
}

dependency "vpc" {
  config_path                             = "../vpc"
  mock_outputs_allowed_terraform_commands = ["plan", "validate", "init"]
  mock_outputs = {
    vpc_id          = "vpc-mock"
    private_subnets = ["subnet-a", "subnet-b", "subnet-c"]
    intra_subnets   = ["subnet-d", "subnet-e", "subnet-f"]
  }
}

inputs = {
  name               = include.root.locals.name
  kubernetes_version = include.root.locals.env.k8s_version

  vpc_id                   = dependency.vpc.outputs.vpc_id
  subnet_ids               = dependency.vpc.outputs.public_subnets
  control_plane_subnet_ids = dependency.vpc.outputs.intra_subnets

  endpoint_public_access       = true                # lab: kubectl do notebook
  endpoint_public_access_cidrs = [get_env("MEU_IP")] # export MEU_IP=$(curl -s https://checkip.amazonaws.com)/32

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  addons = {
    vpc-cni = {
      before_compute = true
      configuration_values = jsonencode({
        env = { ENABLE_PREFIX_DELEGATION = "true", WARM_PREFIX_TARGET = "1" }
      })
    }
    eks-pod-identity-agent = { before_compute = true }
    coredns                = {}
    kube-proxy             = {}
  }

  # nó fixo e pequeno: é onde o Karpenter e o ArgoCD moram
  eks_managed_node_groups = {
    sistema = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2
    }
  }

  node_security_group_tags = { "karpenter.sh/discovery" = include.root.locals.name }
  deletion_protection      = false
}
