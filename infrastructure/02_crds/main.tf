# Define a null_resource to configure Kubeconfig
resource "null_resource" "kubeconfig" {
  provisioner "local-exec" {
    command = "kubectl cluster-info --context kind-cluster-playground"
  }
}

# Create the linkerd namespace
resource "kubernetes_namespace" "linkerd" {
  depends_on = [null_resource.kubeconfig]

  metadata {
    name = "linkerd"
  }
}

# Deploy Linkerd CRDs with Helm
resource "helm_release" "linkerd-crds" {
  name = "linkerd-crds"
  namespace = "linkerd"

  repository = "https://helm.linkerd.io/stable"
  chart = "linkerd-crds"
  version = "1.8.0"
}

# Add automatic proxy injection to default namespace.
resource "null_resource" "inject_linkerd_proxy_in_default_namespace" {
  provisioner "local-exec" {
    command = "kubectl annotate --overwrite namespace default linkerd.io/inject=enabled"
  }
}

# Create the namespace for emissary
resource "kubernetes_namespace" "emissary" {
  depends_on = [null_resource.kubeconfig]

  metadata {
    name = "emissary"
    annotations = {
      "linkerd.io/inject": "enabled"
    }
  }
}

# Create the namespace for the emissary system
resource "kubernetes_namespace" "emissary-system" {
  depends_on = [null_resource.kubeconfig]

  metadata {
    name = "emissary-system"
    annotations = {
      "linkerd.io/inject": "enabled"
    }
  }
}

# Install Emissary CRDs
# See https://www.getambassador.io/docs/emissary/latest/topics/install/helm
resource "null_resource" "emissary-crds" {
  depends_on = [kubernetes_namespace.emissary-system]

  provisioner "local-exec" {
    command = "kubectl apply -f https://app.getambassador.io/yaml/emissary/3.8.0/emissary-crds.yaml"
  }
}

# Wait for emissary-apiext to be deployed
# See https://www.getambassador.io/docs/emissary/latest/topics/install/helm
resource "null_resource" "emissary-apiext" {
  depends_on = [null_resource.emissary-crds]

  provisioner "local-exec" {
    command = "kubectl wait --timeout=600s --for=condition=available deployment emissary-apiext -n emissary-system"
  }
}

# Create the namespace for cert-manager
resource "kubernetes_namespace" "cert-manager" {
  metadata {
    name = "cert-manager"
    annotations = {
      "linkerd.io/inject": "disabled"
    }
  }
}

# cert-manager
module "cert-manager" {
  depends_on = [kubernetes_namespace.cert-manager]
  source  = "terraform-iaac/cert-manager/kubernetes"
  version = "2.6.0"

  create_namespace = false
  cluster_issuer_email = "admin@cluster.playground"
  cluster_issuer_create = false
  # cluster_issuer_name                    = "cert-manager-global"
  # cluster_issuer_private_key_secret_name = "cert-manager-private-key"
}

resource "helm_release" "trust-manager" {
  depends_on = [module.cert-manager]

  name = "trust-manager"
  namespace = "cert-manager"

  repository = "https://charts.jetstack.io"
  chart = "trust-manager"
  version = "0.6.0"

  wait = true
}
