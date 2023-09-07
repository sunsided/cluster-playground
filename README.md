# ASP.NET Core on Kubernetes

## Prerequisites

- Terraform
- Docker
- KIND, e.g. from [kubernetes-sigs/kind](https://github.com/kubernetes-sigs/kind/releases)
- Helm
- step, e.g. from [Install step](https://smallstep.com/docs/step-cli/installation/)

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

First, create the kind cluster. This first needs to pull the [kindest/node](https://hub.docker.com/r/kindest/node/)
Docker image, which may take some time.

```shell
cd infastructure/01_kind
terraform init
terraform plan -out kind.tfplan
TF_LOG=info terraform apply kind.tfplan
```

Next, provision namespaces and CRDs:

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

Finally, provision service mappings for Emissary:

```shell
cd infastructure/04_mappings
terraform init
terraform plan -out mappings.tfplan
TF_LOG=info terraform apply mappings.tfplan
```
