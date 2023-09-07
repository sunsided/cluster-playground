resource "kubernetes_manifest" "linkerd-trust-anchor-cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata   = {
      name      = "cluster-playground"
      namespace = "emissary"
    }
    spec = {
      secretName = "emissary-certs-cluster-playground"
      issuerRef  = {
        name = "linkerd-self-signed-issuer"
        kind = "ClusterIssuer"
      }
      commonName = "cluster.playground"
      dnsNames   = [
        "cluster-playground",
        "cluster.playground",
        "linkerd.cluster-playground",
        "linkerd.cluster.playground",
        "*.cluster.playground",
        "*.cluster-playground"
      ]
    }
  }
}

# Create a listener for Emissary
# See also:
# - https://www.getambassador.io/docs/emissary/latest/topics/running/listener
resource "kubernetes_manifest" "emissary-listener-http" {
  manifest = {
    apiVersion = "getambassador.io/v3alpha1"
    kind       = "Listener"
    metadata   = {
      name      = "emissary-ingress-http-listener"
      namespace = "emissary"
    }
    spec = {
      port        = 8080
      protocol    = "HTTP"
      securityModel = "XFP"
      l7Depth     = 0
      hostBinding = {
        namespace = {
          from = "ALL"
        }
      }
    }
  }
}

# Create a listener for Emissary
# See also:
# - https://www.getambassador.io/docs/emissary/latest/topics/running/listener
resource "kubernetes_manifest" "emissary-listener-https" {
  manifest = {
    apiVersion = "getambassador.io/v3alpha1"
    kind       = "Listener"
    metadata   = {
      name      = "emissary-ingress-https-listener"
      namespace = "emissary"
    }
    spec = {
      port        = 8443
      protocol    = "HTTPS"
      securityModel = "XFP"
      l7Depth     = 0
      hostBinding = {
        namespace = {
          from = "ALL"
        }
      }
    }
  }
}

# Create a Host for Emissary
resource "kubernetes_manifest" "emissary-host-catchall" {
  manifest = {
    apiVersion = "getambassador.io/v3alpha1"
    kind       = "Host"
    metadata   = {
      name      = "catchall"
      namespace = "emissary"
    }
    spec = {
      hostname        = "*"
      mappingSelector = {
        matchLabels = {
          host = "catchall"
        }
      }
      requestPolicy = {
        insecure = {
          action = "Route"
        }
      }
      tlsSecret = {
        name      = "emissary-certs-cluster-playground"
        namespace = "emissary"
      }
    }
  }
}

# Create a Host for Emissary
resource "kubernetes_manifest" "emissary-host-linkerd-http" {
  manifest = {
    apiVersion = "getambassador.io/v3alpha1"
    kind       = "Host"
    metadata   = {
      name      = "linkerd-http"
      namespace = "emissary"
    }
    spec = {
      hostname        = "linkerd.cluster-playground:38080" # port needs to be included
      mappingSelector = {
        matchLabels = {
          host = "linkerd"
        }
      }
      requestPolicy = {
        insecure = {
          action = "Route"
        }
      }
    }
  }
}

resource "kubernetes_manifest" "emissary-host-linkerd-https" {
  manifest = {
    apiVersion = "getambassador.io/v3alpha1"
    kind       = "Host"
    metadata   = {
      name      = "linkerd-https"
      namespace = "emissary"
    }
    spec = {
      hostname        = "linkerd.cluster-playground:38443" # port needs to be included
      mappingSelector = {
        matchLabels = {
          host = "linkerd"
        }
      }
      requestPolicy = {
        insecure = {
          action = "Route"
        }
      }
      tlsSecret = {
        name      = "emissary-certs-cluster-playground"
        namespace = "emissary"
      }
    }
  }
}

# Create a mapping for Linkerd Viz
# See also:
# - https://www.getambassador.io/docs/emissary/latest/topics/using/rewrites
resource "kubernetes_manifest" "linkerd-viz-mapping" {
  manifest = {
    apiVersion = "getambassador.io/v3alpha1"
    kind       = "Mapping"
    metadata   = {
      name      = "linkerd-viz"
      namespace = "emissary"
      labels    = {
        host = "linkerd"
      }
    }
    spec = {
      # Linkerd Viz disallows public access by default; spoof localhost.
      host_rewrite  = "localhost"
      prefix        = "/"
      service       = "http://web.linkerd:8084"
      allow_upgrade = [
        "spdy/3.1",
        "websocket"
      ]
    }
  }
}

# Deploy httpbin for testing
resource "kubernetes_deployment" "httpbin" {
  metadata {
    name      = "httpbin"
    namespace = "default"
    labels    = {
      app = "httpbin"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "httpbin"
      }
    }

    template {
      metadata {
        labels = {
          app = "httpbin"
        }
      }

      spec {
        container {
          image = "kennethreitz/httpbin"
          name  = "httpbin"

          resources {
            limits = {
              cpu    = "0.5"
              memory = "256Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "50Mi"
            }
          }

          port {
            container_port = 80
            name           = "http"
          }

          liveness_probe {
            http_get {
              path = "/status/200"
              port = 80
            }

            initial_delay_seconds = 3
            period_seconds        = 3
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "httpbin" {
  metadata {
    name      = "httpbin"
    namespace = "default"
    labels    = {
      app = "httpbin"
    }
  }
  spec {
    selector = {
      app = "httpbin"
    }
    session_affinity = "ClientIP"
    port {
      port        = 80
      target_port = 80
    }
  }
}

resource "kubernetes_manifest" "httpbin-mapping" {
  depends_on = [kubernetes_service.httpbin]
  manifest = {
    apiVersion = "getambassador.io/v3alpha1"
    kind       = "Mapping"
    metadata   = {
      name      = "httpbin"
      namespace = "emissary"
      labels    = {
        host = "catchall"
      }
    }
    spec = {
      prefix        = "/httpbin"
      service       = "http://httpbin.default"
      allow_upgrade = [
        "spdy/3.1",
        "websocket"
      ]
    }
  }
}
