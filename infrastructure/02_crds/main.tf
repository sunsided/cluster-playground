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
