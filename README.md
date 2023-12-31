# ASP.NET Core on Kubernetes (kindly terraformed)

**This is a work in progress.** This project is meant to provide a starting point to experiment with
ASP.NET Core HTTP/2 and HTTP/3 hosting on [linkerd]-meshed [Kubernetes]. [Terraform] files are provided
to bootstrap a [Kubernetes-in-Docker] cluster, using [Emissary-Ingress] (formerly _Ambassador_) ingress.

Certificates are issued from a self-signed CA managed by [cert-manager] and bundled by [trust-manager]. Specifically,
Let's Encrypt is not used as an ACME provider since no public internet access is given.

[Kubernetes]: https://kubernetes.io/
[linkerd]: https://linkerd.io/
[Terraform]: https://www.terraform.io/
[cert-manager]: https://cert-manager.io/
[trust-manager]: https://cert-manager.io/docs/projects/trust-manager
[Emissary-Ingress]: https://www.getambassador.io/products/api-gateway
[Kubernetes-in-Docker]: https://kind.sigs.k8s.io/

---

The kind setup (bootstrapped with Terraform, see below) assumes that services are reachable under the
domain `cluster-playground` at port `38080` (HTTP) and `38443` (HTTPS). Specifically, the Linkerd dashboard
is available at `http://linkerd.cluster-playground:38080` or `https://linkerd.cluster-playground:38443`.
You will need to make sure that your DNS contains proper redirects to the IP of the
`cluster-playground-control-plane` Docker container, which should listen at `0.0.0.0:38080` and `0.0.0.0:38443`
respectively. You may want to fiddle with your `/etc/hosts` table.

See [infrastructure/04_mappings/main.tf](infrastructure/04_mappings/main.tf) for more details.

## Prerequisites

- Terraform
- Docker
- KIND, e.g. from [kubernetes-sigs/kind](https://github.com/kubernetes-sigs/kind/releases)
- Helm

### Installing Terraform

Install Terraform e.g. via:

```shell
snap install terraform
```

We'll be making use of the `tehcyx/kind` provider available at [tehcyx/terraform-provider-kind](https://github.com/tehcyx/terraform-provider-kind). 

### Installing Helm

Install helm e.g. via:

```shell
snap install helm
```

## Provisioning the cluster

The cluster provisioning is split into multiple steps. This is suboptimal but is currently required to decouple
dependencies between CRDs dynamically created in one step but statically verified in another.

First, create the kind cluster. This first needs to pull the [kindest/node](https://hub.docker.com/r/kindest/node/)
Docker image, which may take some time.

```shell
cd infastructure/01_kind
terraform init
terraform plan -out kind.tfplan
TF_LOG=info terraform apply kind.tfplan
```

Next, provision namespaces and CRDs, cert-manager, trust-manager, etc.:

```shell
cd infastructure/02_crds
terraform init
terraform plan -out crds.tfplan
TF_LOG=info terraform apply crds.tfplan
```

Next, provision linkerd, Emissary, etc.:

```shell
cd infastructure/03_linkerd
terraform init
terraform plan -out linkerd.tfplan
TF_LOG=info terraform apply linkerd.tfplan
```

Finally, provision service mappings for Emissary, additional certificates, etc.:

```shell
cd infastructure/04_mappings
terraform init
terraform plan -out mappings.tfplan
TF_LOG=info terraform apply mappings.tfplan
```
