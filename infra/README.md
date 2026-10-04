# infra

```text
live/<cliente>/<ambiente>/<região>/<unit>
         client.hcl  env.hcl   region.hcl
```

Nova região ou ambiente: copia a pasta e muda o `.hcl` dela.

## Subir

```bash
export AWS_PROFILE=poczinha
export MEU_IP=$(curl -s https://checkip.amazonaws.com)/32

cd live/lab/shared/us-east-1/ecr
terragrunt backend bootstrap        # cria o bucket de state, uma vez só
terragrunt apply

cd ../../../dev/us-east-1
terragrunt run --all apply          # vpc, eks, depois karpenter e lb-controller
```

## Desmontar

Primeiro o que o cluster criou fora do Terraform (Ingress, que vira ALB). Depois:

```bash
cd live/lab/dev/us-east-1 && terragrunt run --all destroy
```
