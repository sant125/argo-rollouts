# Repositório compartilhado: dev e prod puxam a mesma imagem (prod so promove a imagem, nao builda novamente)
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "tfr:///terraform-aws-modules/ecr/aws?version=3.2.0"
}

inputs = {
  repository_name                 = "rollout-demo"
  repository_image_tag_mutability = "IMMUTABLE" # tag não anda: v2 é sempre a mesma v2
  repository_image_scan_on_push   = true
  repository_force_delete         = true # lab: destroy apaga mesmo com imagem dentro
  repository_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantém só as 10 imagens mais recentes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
