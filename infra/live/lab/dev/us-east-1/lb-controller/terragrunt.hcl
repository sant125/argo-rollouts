# Só a role e a associação do Pod Identity. O chart vai pelo ArgoCD,
# criando a service account com o nome abaixo.
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "tfr:///terraform-aws-modules/eks-pod-identity/aws?version=2.9.0"
}

dependency "eks" {
  config_path                             = "../eks"
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
  mock_outputs                            = { cluster_name = "mock" }
}

inputs = {
  name                            = "${include.root.locals.name}-aws-lb-controller"
  attach_aws_lb_controller_policy = true
  associations = {
    this = {
      cluster_name    = dependency.eks.outputs.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}
