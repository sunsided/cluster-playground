# Define a null_resource to configure Kubeconfig
resource "null_resource" "kubeconfig" {
  provisioner "local-exec" {
    command = "kubectl cluster-info --context kind-cluster-playground"
  }
}

# Create the CA certificates
resource "null_resource" "generate-ca-cert" {
  provisioner "local-exec" {
    command = "step certificate create root.linkerd.cluster.local ca.crt ca.key --profile root-ca --no-password --insecure"
  }
}

data "local_file" "ca-certificate" {
  depends_on = [null_resource.generate-ca-cert]
  filename = "${path.module}/ca.crt"
}

# Create the mTLS issuer certificates
resource "null_resource" "generate-issuer-cert" {
  depends_on = [null_resource.generate-ca-cert]

  provisioner "local-exec" {
    command = "step certificate create identity.linkerd.cluster.local issuer.crt issuer.key --profile intermediate-ca --not-after 8760h --no-password --insecure --ca ca.crt --ca-key ca.key"
  }
}

data "local_file" "issuer-certificate" {
  depends_on = [null_resource.generate-issuer-cert]
  filename = "${path.module}/issuer.crt"
}

data "local_file" "issuer-key" {
  depends_on = [null_resource.generate-issuer-cert]
  filename = "${path.module}/issuer.key"
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

# Deploy Linkerd Control Plane with Helm
#
# Will require mTLS root certificates - see https://linkerd.io/2.14/tasks/generate-certificates/
resource "helm_release" "linkerd-control-plane" {
  depends_on = [
    helm_release.linkerd-crds,
    null_resource.generate-issuer-cert
  ]

  name = "linkerd-control-plane"
  namespace = "linkerd"

  repository = "https://helm.linkerd.io/stable"
  chart = "linkerd-control-plane"
  version = "1.15.0"

  set {
    name  = "identityTrustAnchorsPEM"
    value = data.local_file.ca-certificate.content
    type = "string"
  }

  set {
    name  = "identity.issuer.tls.crtPEM"
    value = data.local_file.issuer-certificate.content
    type = "string"
  }

  set {
    name  = "identity.issuer.tls.keyPEM"
    value = data.local_file.issuer-key.content
    type = "string"
  }
}

# Deploy Linkerd Viz with Helm
resource "helm_release" "linkerd-viz" {
  depends_on = [helm_release.linkerd-control-plane]

  name = "linkerd-viz"
  namespace = "linkerd"

  repository = "https://helm.linkerd.io/stable"
  chart = "linkerd-viz"
  version = "30.11.0"
}
