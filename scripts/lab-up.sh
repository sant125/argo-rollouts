#!/usr/bin/env bash
# Sobe o lab inteiro: infra (Terragrunt) → imagem no ECR → kubeconfig → ArgoCD → root app.
# Pode rodar de novo sem medo: o que já existe fica como está.
#
#   ./scripts/lab-up.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

preflight

# ---------------------------------------------------------------- state
if ! aws s3api head-bucket --bucket "$STATE_BUCKET" >/dev/null 2>&1; then
  log "Bucket de state não existe: criando ($STATE_BUCKET)"
  (cd "$LIVE/shared/us-east-1/ecr" && tg backend bootstrap)
fi

# ---------------------------------------------------------------- infra
log "Terragrunt apply: ecr, vpc, eks, karpenter, lb-controller"
(cd "$LIVE" && tg run --all -- apply -auto-approve)

# ---------------------------------------------------------------- outputs → manifests
# O ArgoCD lê do Git, então valores que saem do Terraform precisam estar commitados.
log "Conferindo os manifests com os outputs do Terraform"
vpc_id=$(tg_out "$DEV/vpc" vpc_id)
queue=$(tg_out "$DEV/karpenter" queue_name)
node_role=$(tg_out "$DEV/karpenter" node_iam_role_name)
repo_url=$(tg_out "$LIVE/shared/us-east-1/ecr" repository_url)

lb=$ROOT/gitops/argocd/lb-controller.yaml
karp=$ROOT/gitops/argocd/karpenter.yaml
np=$ROOT/gitops/platform/karpenter/nodepool.yaml

sed -E -i "s|^(\s*vpcId:\s*).*|\1\"$vpc_id\"|" "$lb"
sed -E -i "s|^(\s*interruptionQueue:\s*).*|\1\"$queue\"|" "$karp"
sed -E -i "s|^(\s*role:\s*)[^ #]+|\1$node_role|" "$np"

if ! git -C "$ROOT" diff --quiet -- "$lb" "$karp" "$np"; then
  git -C "$ROOT" --no-pager diff -- "$lb" "$karp" "$np"
  if confirm "Os outputs mudaram. Commit + push pra main (o ArgoCD lê de lá)?"; then
    git -C "$ROOT" add -- "$lb" "$karp" "$np"
    git -C "$ROOT" commit -m "lab: atualiza manifests com outputs do terraform" -- "$lb" "$karp" "$np"
    git -C "$ROOT" push
  else
    warn "Sem push, o ArgoCD vai aplicar os valores antigos que estão no Git."
  fi
else
  echo "vpcId, interruptionQueue e role já batem com o Terraform."
fi

# ---------------------------------------------------------------- imagem
tag=$(sed -nE 's/^\s*newTag:\s*"?([^" #]+)"?.*/\1/p' "$ROOT/gitops/apps/demo/overlays/dev/kustomization.yaml" | head -1)
log "Imagem $repo_url:$tag"
# sem o usuário no grupo docker, cai pro sudo (pede a senha)
DOCKER=docker
docker info >/dev/null 2>&1 || DOCKER="sudo docker"
if aws ecr describe-images --repository-name "${repo_url##*/}" --image-ids imageTag="$tag" >/dev/null 2>&1; then
  echo "Já está no ECR."
elif $DOCKER info >/dev/null 2>&1; then
  aws ecr get-login-password | $DOCKER login --username AWS --password-stdin "${repo_url%%/*}"
  $DOCKER build -t "$repo_url:$tag" "$ROOT/app"
  $DOCKER push "$repo_url:$tag"
else
  warn "Imagem não está no ECR e o Docker não está acessível. O demo-dev vai ficar em ImagePullBackOff até você fazer o push."
fi

# ---------------------------------------------------------------- cluster
log "kubeconfig ($CLUSTER)"
kubeconfig

log "ArgoCD $ARGOCD_CHART_VERSION"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
  --version "$ARGOCD_CHART_VERSION" --wait --timeout 10m

log "Root app (app of apps)"
kubectl apply -f "$ROOT/gitops/bootstrap/root.yaml"

# ---------------------------------------------------------------- resumo
log "Esperando o ALB do demo (até 10 min; pode sair com Ctrl+C sem problema)"
host=""
for _ in $(seq 60); do
  host=$(kubectl -n demo get ingress rollout-demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [[ -n $host ]] && break
  sleep 10
done

pass=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
cat <<EOF

Pronto.
  ArgoCD:  kubectl -n argocd port-forward svc/argocd-server 8080:443  →  https://localhost:8080
           usuário admin | senha ${pass:-"(kubectl -n argocd get secret argocd-initial-admin-secret)"}
  Demo:    ${host:+http://$host  (o DNS do ALB leva uns minutos pra propagar)}${host:-"ingress ainda sem endereço: kubectl -n demo get ingress"}
  Apps:    kubectl -n argocd get applications
EOF
