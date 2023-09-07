# Create a listener for Emissary
# See also:
# - https://www.getambassador.io/docs/emissary/latest/topics/running/listener
resource "kubernetes_manifest" "emissary-listener-http" {
  manifest = {
    apiVersion = "getambassador.io/v3alpha1"
    kind = "Listener"
    metadata = {
      name = "emissary-ingress-http-listener"
      namespace = "emissary"
    }
    spec = {
      port = 8080
      protocol = "HTTP"
      securityModel: "XFP"
      l7Depth = 0
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
    kind = "Listener"
    metadata = {
      name = "emissary-ingress-https-listener"
      namespace = "emissary"
    }
    spec = {
      port = 8443
      protocol = "HTTPS"
      securityModel: "XFP"
      l7Depth = 0
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
    kind = "Host"
    metadata = {
      name = "catchall"
      namespace = "emissary"
    }
    spec = {
      hostname = "*"
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
    }
  }
}

# Create a Host for Emissary
resource "kubernetes_manifest" "emissary-host-linkerd-http" {
  manifest = {
    apiVersion = "getambassador.io/v3alpha1"
    kind = "Host"
    metadata = {
      name = "linkerd-http"
      namespace = "emissary"
    }
    spec = {
      hostname = "linkerd.cluster-playground:38080" # port needs to be included
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
    kind = "Host"
    metadata = {
      name = "linkerd-https"
      namespace = "emissary"
    }
    spec = {
      hostname = "linkerd.cluster-playground:38443" # port needs to be included
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

# Create a mapping for Linkerd Viz
# See also:
# - https://www.getambassador.io/docs/emissary/latest/topics/using/rewrites
resource "kubernetes_manifest" "linkerd-viz-mapping" {
  manifest = {
    apiVersion = "getambassador.io/v3alpha1"
    kind = "Mapping"
    metadata = {
      name = "linkerd-viz"
      namespace = "emissary"
      labels = {
        host = "linkerd"
      }
    }
    spec = {
      # Linkerd Viz disallows public access by default; spoof localhost.
      host_rewrite = "localhost"
      prefix = "/"
      service = "http://web.linkerd:8084"
      allow_upgrade = [
        "spdy/3.1",
        "websocket"
      ]
    }
  }
}
