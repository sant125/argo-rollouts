# Funções e variáveis comuns aos scripts do lab. Não roda sozinho: é carregado por lab-up.sh e lab-down.sh.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LIVE=$ROOT/infra/live/lab
DEV=$LIVE/dev/us-east-1

export AWS_PROFILE=poczinha
export AWS_REGION=us-east-1
export AWS_PAGER=""
ACCOUNT_ID=767866852518
CLUSTER=lab-dev
STATE_BUCKET=lab-tfstate-$ACCOUNT_ID
ARGOCD_CHART_VERSION=10.9.6

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[aviso] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[erro] %s\033[0m\n' "$*" >&2; exit 1; }

# terragrunt sem prompt; logs do terragrunt vão pro stderr
tg() { terragrunt --non-interactive "$@"; }

# output de uma unit: tg_out <dir> <output>
tg_out() { (cd "$1" && terragrunt --non-interactive --log-level error output -raw "$2"); }

preflight() {
  for c in aws terragrunt terraform kubectl helm jq curl; do
    command -v "$c" >/dev/null || die "falta o comando: $c"
  done

  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log "Sessão AWS expirada: abrindo o login SSO"
    aws sso login --profile default
    aws sts get-caller-identity >/dev/null || die "não consegui autenticar na AWS"
  fi

  # o endpoint público do EKS só aceita este IP (eks/terragrunt.hcl)
  MEU_IP="$(curl -fsS https://checkip.amazonaws.com)/32" || die "não consegui descobrir o IP público"
  export MEU_IP
  log "Conta $ACCOUNT_ID | profile $AWS_PROFILE | IP $MEU_IP"
}

cluster_exists() { aws eks describe-cluster --name "$CLUSTER" >/dev/null 2>&1; }

kubeconfig() { aws eks update-kubeconfig --name "$CLUSTER" --alias "$CLUSTER" >/dev/null; }

confirm() {
  local resp
  read -r -p "$1 [y/N] " resp
  [[ $resp =~ ^[yYsS]$ ]]
}
