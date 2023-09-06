# Kind Provider
# https://registry.terraform.io/providers/tehcyx/kind/latest/docs
terraform {
  required_providers {
    kind = {
      source = "tehcyx/kind"
      version = "~> 0.2.1"
    }
  }
}

# Define a Kind cluster resource
resource "kind_cluster" "cluster-playground" {
  name = "cluster-playground"
  wait_for_ready = true

  kind_config {
    kind = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
    }

    node {
      role = "worker"
    }

    node {
      role = "worker"
    }
  }
}
