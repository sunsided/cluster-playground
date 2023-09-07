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

# Deploy Linkerd Control Plane with Helm
#
# Will require mTLS root certificates - see https://linkerd.io/2.14/tasks/generate-certificates/
resource "helm_release" "linkerd-control-plane" {
  depends_on = [null_resource.generate-issuer-cert]

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

# Add automatic proxy injection to default namespace.
resource "null_resource" "inject_linkerd_proxy_in_default_namespace" {
  depends_on = [helm_release.linkerd-control-plane]

  provisioner "local-exec" {
    command = "kubectl annotate --overwrite namespace default linkerd.io/inject=enabled"
  }
}

# Deploy Emissary Ingress (previously Ambassador)
#
# See also:
# - https://linkerd.io/2.14/tasks/using-ingress/#ambassador
# - https://buoyant.io/blog/emissary-and-linkerd-the-best-of-both-worlds
resource "helm_release" "emissary" {
  depends_on = [helm_release.linkerd-control-plane]

  name = "emissary-ingress"
  namespace = "emissary"

  repository = "https://www.getambassador.io"
  chart = "emissary-ingress"
  version = "8.8.0"

  set {
    name  = "replicaCount"
    value = "1"
  }

  set {
    name  = "service.type"
    value = "NodePort"
  }

  wait = true
}

# Patch node selector for Emissary ingress
resource "null_resource" "patch-emissary-ingress" {
  depends_on = [helm_release.emissary]

  provisioner "local-exec" {
    command = "kubectl patch deployment -n emissary emissary-ingress --type merge --patch '{\"spec\": {\"template\": {\"spec\": {\"nodeSelector\": {\"ingress-ready\": \"true\"}, \"tolerations\": [{\"effect\":\"NoSchedule\", \"operator\":\"Exists\", \"key\":\"node-role.kubernetes.io/control-plane\"}, {\"effect\":\"NoSchedule\", \"operator\":\"Exists\", \"key\":\"node-role.kubernetes.io/master\"}]}, \"metadata\": { \"annotations\": { \"prometheus.io/scrape\": \"true\", \"prometheus.io/port\": \"9102\" } }}}}'"
  }
}

# Create a module for Emissary itself
resource "null_resource" "ambassador-module" {
  depends_on = [helm_release.emissary]

  provisioner "local-exec" {
    command = "kubectl patch module -n emissary ambassador --type merge --patch '{\"spec\": {\"config\": {\"add_linkerd_headers\": true}}}'"
  }
}

# Patch ports for Emissary
resource "null_resource" "patch-emissary-ports" {
  depends_on = [helm_release.emissary]

  provisioner "local-exec" {
    command = "kubectl patch deployment -n emissary emissary-ingress --type json --patch '[{\"op\":\"add\", \"path\":\"/spec/template/spec/containers/0/ports\", \"value\":[{\"containerPort\":8080,\"hostPort\":8080,\"name\":\"http\",\"protocol\":\"TCP\"},{\"containerPort\":8443,\"hostPort\":8443,\"name\":\"https\",\"protocol\":\"TCP\"},{\"containerPort\":8877,\"name\":\"admin\",\"protocol\":\"TCP\"}]}]'"
  }
}
