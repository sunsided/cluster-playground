# Create a mapping for Linkerd Viz
# See also:
# - https://www.getambassador.io/docs/emissary/latest/topics/using/rewrites
resource "kubernetes_manifest" "linkerd-viz-mapping" {
  manifest = {
    apiVersion = "getambassador.io/v2"
    kind = "Mapping"
    metadata = {
      name = "linkerd-viz"
      namespace = "emissary"
    }
    spec = {
      prefix = "/linkerd"
      service = "http://web.linkerd:8084"
      rewrite = "/"
      allow_upgrade = [
        "spdy/3.1",
        "websocket"
      ]
    }
  }
}
