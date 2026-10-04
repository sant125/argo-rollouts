# bootstrap

O único passo manual. Depois disso, tudo vem do Git.

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace --version 10.9.6
kubectl apply -f gitops/bootstrap/root.yaml
```

Antes, troque os `TROCAR` (saem do `terragrunt output` de cada unit):

| Arquivo | Campo | De onde |
|---|---|---|
| `argocd/lb-controller.yaml` | `vpcId` | `infra/.../vpc` → `vpc_id` |
| `argocd/karpenter.yaml` | `interruptionQueue` | `infra/.../karpenter` → `queue_name` |
| `platform/karpenter/nodepool.yaml` | `role` | `infra/.../karpenter` → `node_iam_role_name` |
| `apps/demo/overlays/*/kustomization.yaml` | imagem | `infra/.../ecr` → `repository_url` |

E o `repoURL` dos YAMLs aponta pro teu repositório.
