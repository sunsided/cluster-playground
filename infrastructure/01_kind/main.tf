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
      kubeadm_config_patches = [
        <<EOT
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
        EOT
      ]
      extra_port_mappings {
        host_port = 38080
        container_port = 8080 # Emissary
        protocol = "TCP"
      }
      extra_port_mappings {
        host_port = 38443
        container_port = 8443 # Emissary
        protocol = "TCP"
      }
    }

    node {
      role = "worker"
    }

    node {
      role = "worker"
    }
  }
}
