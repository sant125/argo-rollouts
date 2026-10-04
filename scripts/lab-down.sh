#!/usr/bin/env bash
# Derruba o que cobra por hora (EKS, nós, ALB) e mantém o que é de graça (VPC sem NAT, ECR,
# bucket de state), pra próxima subida ser mais rápida.
#
#   ./scripts/lab-down.sh          # derruba lb-controller, karpenter e eks
#   ./scripts/lab-down.sh --tudo   # derruba também vpc e ecr (o bucket de state sempre fica)
#   -y                             # não pergunta antes
set -euo pipefail
source "$(dirname "$0")/lib.sh"

TUDO=false; YES=false
for a in "$@"; do
  case $a in
    --tudo) TUDO=true ;;
    -y) YES=true ;;
    *) die "opção desconhecida: $a" ;;
  esac
done

preflight

units=(lb-controller karpenter eks)
echo "Vai destruir: ${units[*]}$($TUDO && echo ' + vpc + ecr' || true)"
$YES || confirm "Continuar?" || exit 0

# ---------------------------------------------------------------- o que o cluster criou fora do Terraform
# ALB (Ingress / Service LoadBalancer), nós do Karpenter e volumes EBS não estão no state.
# Se ficarem, cobram e travam o destroy da VPC por causa das ENIs.
if cluster_exists; then
  kubeconfig

  if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
    log "Pausando o auto-sync do ArgoCD (senão ele recria o que vou apagar)"
    for app in $(kubectl -n argocd get applications -o name); do
      kubectl -n argocd patch "$app" --type json \
        -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]' >/dev/null 2>&1 || true
    done
  fi

  log "Apagando Ingress e Services LoadBalancer (ALB/NLB)"
  kubectl delete ingress --all -A --wait --timeout=5m || true
  kubectl get svc -A -o json \
    | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' \
    | while read -r ns name; do kubectl -n "$ns" delete svc "$name" --wait --timeout=5m || true; done

  if kubectl get crd nodepools.karpenter.sh >/dev/null 2>&1; then
    log "Apagando NodePools e EC2NodeClasses (nós do Karpenter e o instance profile)"
    kubectl delete nodepools --all --wait --timeout=5m || true
    kubectl delete nodeclaims --all --wait --timeout=5m || true
    kubectl delete ec2nodeclasses --all --wait --timeout=5m || true
  fi

  log "Apagando PVCs (volumes EBS)"
  kubectl delete pvc --all -A --wait --timeout=5m || true

  log "Esperando a AWS remover os load balancers e os nós do Karpenter"
  for _ in $(seq 30); do
    lbs=$(aws resourcegroupstaggingapi get-resources \
      --resource-type-filters elasticloadbalancing:loadbalancer \
      --tag-filters "Key=elbv2.k8s.aws/cluster,Values=$CLUSTER" \
      --query 'length(ResourceTagMappingList)' --output text)
    nodes=$(aws ec2 describe-instances \
      --filters "Name=tag:karpenter.sh/nodepool,Values=*" "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" \
                "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" \
      --query 'length(Reservations[].Instances[])' --output text)
    echo "  load balancers: $lbs | nós karpenter: $nodes"
    [[ $lbs == 0 && $nodes == 0 ]] && break
    sleep 10
  done
else
  warn "Cluster $CLUSTER não existe: pulando a limpeza do Kubernetes."
fi

# ---------------------------------------------------------------- terragrunt
for u in "${units[@]}"; do
  log "Terragrunt destroy: $u"
  (cd "$DEV/$u" && tg destroy -auto-approve)
done

# ---------------------------------------------------------------- sobras fora do state
log "Limpando sobras criadas pelo Karpenter / LB controller"
for ip in $(aws iam list-instance-profiles --query "InstanceProfiles[?starts_with(InstanceProfileName, '${CLUSTER}_')].InstanceProfileName" --output text); do
  for r in $(aws iam get-instance-profile --instance-profile-name "$ip" --query 'InstanceProfile.Roles[].RoleName' --output text); do
    aws iam remove-role-from-instance-profile --instance-profile-name "$ip" --role-name "$r"
  done
  aws iam delete-instance-profile --instance-profile-name "$ip" && echo "  instance profile $ip"
done

for lt in $(aws ec2 describe-launch-templates --filters "Name=tag:karpenter.k8s.aws/cluster,Values=$CLUSTER" \
            --query 'LaunchTemplates[].LaunchTemplateId' --output text); do
  aws ec2 delete-launch-template --launch-template-id "$lt" >/dev/null && echo "  launch template $lt"
done

for sg in $(aws ec2 describe-security-groups --filters "Name=tag:elbv2.k8s.aws/cluster,Values=$CLUSTER" \
            --query 'SecurityGroups[].GroupId' --output text); do
  aws ec2 delete-security-group --group-id "$sg" && echo "  security group $sg" || warn "não deu pra apagar $sg (ainda em uso?)"
done

if aws logs describe-log-groups --log-group-name-prefix "/aws/eks/$CLUSTER/" --query 'logGroups[0]' --output text | grep -q aws; then
  aws logs delete-log-group --log-group-name "/aws/eks/$CLUSTER/cluster" && echo "  log group /aws/eks/$CLUSTER/cluster"
fi

# ---------------------------------------------------------------- vpc e ecr (só com --tudo)
# depois das sobras: security group esquecido pelo LB controller trava o destroy da VPC
if $TUDO; then
  log "Terragrunt destroy: vpc"
  (cd "$DEV/vpc" && tg destroy -auto-approve)
  log "Terragrunt destroy: ecr"
  (cd "$LIVE/shared/us-east-1/ecr" && tg destroy -auto-approve)
fi

# ---------------------------------------------------------------- conferência
log "O que ainda existe e cobra por hora (tem que estar tudo zerado)"
printf '  %-16s %s\n' \
  "EKS"            "$(aws eks list-clusters --query 'length(clusters)' --output text)" \
  "EC2 ligadas"    "$(aws ec2 describe-instances --filters Name=instance-state-name,Values=pending,running --query 'length(Reservations[].Instances[])' --output text)" \
  "NAT"            "$(aws ec2 describe-nat-gateways --filter Name=state,Values=pending,available --query 'length(NatGateways)' --output text)" \
  "Elastic IP"     "$(aws ec2 describe-addresses --query 'length(Addresses)' --output text)" \
  "Load balancers" "$(aws elbv2 describe-load-balancers --query 'length(LoadBalancers)' --output text)" \
  "Volumes EBS"    "$(aws ec2 describe-volumes --query 'length(Volumes)' --output text)"

$TUDO || echo -e "\nFicaram (sem custo por hora): VPC, ECR e o bucket $STATE_BUCKET."
