# Só o lado da AWS: role do controller (Pod Identity), fila SQS + EventBridge
# de interrupção, role e access entry dos nós. O chart vai pelo ArgoCD.
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "tfr:///terraform-aws-modules/eks/aws//modules/karpenter?version=21.26.0"
}

dependency "eks" {
  config_path                             = "../eks"
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
  mock_outputs                            = { cluster_name = "mock" }
}

inputs = {
  cluster_name = dependency.eks.outputs.cluster_name
  # nome fixo: o EC2NodeClass (gitops/platform/karpenter/nodepool.yaml) referencia a role por nome
  node_iam_role_name            = "${include.root.locals.name}-karpenter-node"
  node_iam_role_use_name_prefix = false
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}
