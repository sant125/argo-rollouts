locals {
  name        = "dev"
  vpc_cidr    = "10.0.0.0/16"
  single_nat  = true   # prod: false (um NAT por AZ)
  k8s_version = "1.xx" # aws eks describe-cluster-versions
}
