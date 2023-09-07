# Kubernetes provider
# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
provider "kubernetes" {
  config_path = "~/.kube/config"
  config_context = "kind-cluster-playground"
}
