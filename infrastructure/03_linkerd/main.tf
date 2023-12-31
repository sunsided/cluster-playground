resource "kubernetes_manifest" "linkerd-self-signed-issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind = "ClusterIssuer"
    metadata = {
      name = "linkerd-self-signed-issuer"
    }
    spec = {
      selfSigned = {}
    }
  }
}

resource "kubernetes_manifest" "linkerd-trust-anchor-issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind = "ClusterIssuer"
    metadata = {
      name = "linkerd-trust-anchor"
    }
    spec = {
      ca = {
        secretName = "linkerd-identity-trust-roots"
      }
    }
  }
}

resource "kubernetes_manifest" "linkerd-trust-anchor-cert" {
  depends_on = [kubernetes_manifest.linkerd-trust-anchor-issuer]
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind = "Certificate"
    metadata = {
      name = "linkerd-trust-anchor"
      namespace = "cert-manager"
    }
    spec = {
      isCA = true
      commonName = "root.linkerd.cluster.local"
      secretName = "linkerd-identity-trust-roots"
      privateKey = {
        algorithm = "ECDSA"
        size = 256
      }
      issuerRef = {
        name = "linkerd-self-signed-issuer"
        kind = "ClusterIssuer"
        group = "cert-manager.io"
      }
    }
  }
}

# Create issuer certificate and linkerd namespace. This will give us a namespace scoped issuer to be used by linkerd
# (and it will also create the issuer secret we need to install linkerd):
resource "kubernetes_manifest" "linkerd-identity-issuer" {
  depends_on = [kubernetes_manifest.linkerd-trust-anchor-issuer]
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind = "Certificate"
    metadata = {
      name = "linkerd-identity-issuer"
      namespace = "linkerd"
    }
    spec = {
      isCA = true
      commonName = "identity.linkerd.cluster.local"
      secretName = "linkerd-identity-issuer"
      duration = "48h0m0s"
      renewBefore: "25h0m0s"
      issuerRef = {
        name = "linkerd-trust-anchor"
        kind = "ClusterIssuer"
      }
      dnsNames = ["identity.linkerd.cluster.local"]
      privateKey = {
        algorithm = "ECDSA"
      }
      usages = [
        "cert sign",
        "crl sign",
        "server auth",
        "client auth"
      ]
    }
  }
}

# Create a Bundle resource to distribute CA certificate in linkerd namespace as a configmap
# (source is taken from the namespace trust was installed in, i.e cert-manager):
resource "kubernetes_manifest" "linkerd-identity-trust-roots" {
  depends_on = [kubernetes_manifest.linkerd-trust-anchor-issuer]
  manifest = {
    apiVersion = "trust.cert-manager.io/v1alpha1"
    kind = "Bundle"
    metadata = {
      name = "linkerd-identity-trust-roots"
    }
    spec = {
      sources = [
        {
          secret = {
            name = "linkerd-identity-trust-roots"
            key = "ca.crt"
          }
        }
      ]
      target = {
        configMap = {
          key = "ca-bundle.crt"
        }
      }
    }
  }
}

# Deploy Linkerd Control Plane with Helm
#
# Will require mTLS root certificates - see https://linkerd.io/2.14/tasks/generate-certificates/
resource "helm_release" "linkerd-control-plane" {
  depends_on = [
    # null_resource.generate-issuer-cert,
    kubernetes_manifest.linkerd-identity-trust-roots]

  name = "linkerd-control-plane"
  namespace = "linkerd"

  repository = "https://helm.linkerd.io/stable"
  chart = "linkerd-control-plane"
  version = "1.15.0"

  set {
    name  = "identity.issuer.scheme"
    value = "kubernetes.io/tls"
  }

  set {
    name = "identity.externalCA"
    value = "true"
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

  set {
    name = "createDefaultListeners"
    value = "false"
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
    command = "kubectl patch deployment -n emissary emissary-ingress --type json --patch '[{\"op\":\"replace\", \"path\":\"/spec/template/spec/containers/0/ports\", \"value\":[{\"containerPort\":8080,\"hostPort\":8080,\"name\":\"http\",\"protocol\":\"TCP\"},{\"containerPort\":8443,\"hostPort\":8443,\"name\":\"https\",\"protocol\":\"TCP\"},{\"containerPort\":8877,\"name\":\"admin\",\"protocol\":\"TCP\"}]}]'"
  }
}
