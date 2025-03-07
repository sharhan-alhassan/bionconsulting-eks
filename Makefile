
# Default environment if not provided (can be staging, combined, or production)
ENV_FILE ?=

# Load variables from .env
## How to run - make ENV_FILE=.env create-external-dns

ifeq ($(ENV_FILE),)
    ENV ?= staging
else
    ifeq ("$(wildcard $(ENV_FILE))","")
        $(error ENV_FILE '$(ENV_FILE)' does not exist)
    endif
    include $(ENV_FILE)
    export $(shell sed 's/=.*//' $(ENV_FILE))
endif


# Directories and file paths for backends and variable files
BACKEND_DIR = ./backends
VARS_DIR = ./environments
BACKEND_FILE = $(BACKEND_DIR)/backend-$(ENV).tf
VARS_FILE = $(VARS_DIR)/$(ENV).tfvars

# Additional parameters for hosted-zone and external-dns
# These should be provided on the command-line when invoking the targets.
# e.g., make create-hosted-zone PARENT_ZONE=dabafinance.com ZONE=daba-dev.dabafinance.com
PARENT_ZONE ?=
ZONE ?=

# For external-dns, pass in the IAM role ARN, domain filter, and hosted zone ID.
# e.g., make create-external-dns EXTERNAL_DNS_ROLE=arn:aws:iam::265780179050:role/daba-dev-externaldns_route53 DOMAIN_FILTER=daba-dev.dabafinance.com HOSTED_ZONE_ID=Z06387371KFHB1L85IBKG
EXTERNAL_DNS_ROLE ?=
DOMAIN_FILTER ?=
HOSTED_ZONE_ID ?=

# For cluster-autoscaler, pass in CLUSTER_NAME and CLUSTER_AUTOSCALER_ROLE.
# Example:
# make cluster-autoscaler CLUSTER_NAME=daba-dev CLUSTER_AUTOSCALER_ROLE=arn:aws:iam::265780179050:role/daba-dev-eks-cluster-autoscaler
CLUSTER_NAME ?=
CLUSTER_AUTOSCALER_ROLE ?=

.PHONY: init workspace fmt validate plan apply destroy clean add-users create-hosted-zone cluster-autoscaler metrics-server create-external-dns create-ingress-controller create-certmanager create-issuer

## Initialize Terraform and copy backend configuration
init:
	@if [ "$(ENV)" != "staging" ] && [ "$(ENV)" != "combined" ] && [ "$(ENV)" != "production" ]; then \
		echo "Usage: make [init|workspace|plan|apply|destroy] ENV=[staging|combined|production]"; \
		exit 1; \
	fi
	@echo "Deploying to $(ENV) environment..."
	@echo "Copying $(BACKEND_FILE) to backend.tf..."
	cp $(BACKEND_FILE) backend.tf
	@echo "Initializing Terraform..."
	terraform init

## Select or create workspace
workspace:
	@terraform workspace select $(ENV) || terraform workspace new $(ENV)

## Format and validate Terraform configuration
fmt:
	@terraform fmt
	@terraform validate

## Refresh Terraform configuration
refresh:
	@terraform refresh -var-file=$(VARS_FILE)


## Terraform Plan
plan:
	@terraform plan -var-file=$(VARS_FILE) -out=tfplan

## Terraform Apply
apply:
	@terraform apply -var-file=$(VARS_FILE) -auto-approve

## Terraform Destroy
destroy:
	@terraform destroy -var-file=$(VARS_FILE) -auto-approve
	rm -f backend.tf

## Clean backend file (optional)
clean:
	rm -f backend.tf

## Additional activities

# add-users: Apply AWS auth configuration via kubectl.
add-users:
	cd add-ons/permissions && kubectl apply -f aws-auth.yml && cd ../../

# create-hosted-zone: Use provided PARENT_ZONE and ZONE variables in the script.
# Usage: make create-hosted-zone PARENT_ZONE=<parent-zone> ZONE=<subdomain-zone>
create-hosted-zone:
	@if [ -z "$(PARENT_ZONE)" ] || [ -z "$(ZONE)" ]; then \
		echo "Usage: make create-hosted-zone PARENT_ZONE=<parent-zone> ZONE=<subdomain-zone>"; \
		exit 1; \
	fi
	cd add-ons/hosted-zone && PARENT_ZONE=$(PARENT_ZONE) ZONE=$(ZONE) ./create-hz.sh && cd ../../

# cluster-autoscaler: Apply the cluster autoscaler YAML.
cluster-autoscaler:
	@if [ -z "$(CLUSTER_NAME)" ] || [ -z "$(CLUSTER_AUTOSCALER_ROLE)" ]; then \
		echo "Usage: make cluster-autoscaler CLUSTER_NAME=<cluster name> CLUSTER_AUTOSCALER_ROLE=<role arn>"; \
		exit 1; \
	fi
	@echo "Deploying Cluster Autoscaler for cluster $(CLUSTER_NAME) with role $(CLUSTER_AUTOSCALER_ROLE)..."
	cd add-ons/clusterautoscaler && envsubst < cluster-autoscaler.yml > cluster-autoscaler.tmp.yml && kubectl apply -f cluster-autoscaler.tmp.yml && rm cluster-autoscaler.tmp.yml && cd ../../

# metrics-server: Install metrics-server.
metrics-server:
	kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# create-external-dns: Create namespace, service account, annotate, and apply external-dns YAML.
# Usage: make create-external-dns EXTERNAL_DNS_ROLE=<role-arn> DOMAIN_FILTER=<domain> HOSTED_ZONE_ID=<hosted_zone_id>
create-external-dns:
	@if [ -z "$(EXTERNAL_DNS_ROLE)" ] || [ -z "$(DOMAIN_FILTER)" ] || [ -z "$(HOSTED_ZONE_ID)" ]; then \
		echo "Usage: make create-external-dns EXTERNAL_DNS_ROLE=<role-arn> DOMAIN_FILTER=<domain> HOSTED_ZONE_ID=<hosted_zone_id>"; \
		exit 1; \
	fi
	kubectl create namespace external-dns || true
	kubectl create -n external-dns serviceaccount external-dns || true
	kubectl annotate serviceaccount -n external-dns external-dns eks.amazonaws.com/role-arn=$(EXTERNAL_DNS_ROLE) --overwrite
	@echo "Substituting variables in external-dns YAML..."
	cd add-ons/external-dns && envsubst < external-dns.yml > external-dns.tmp.yml && kubectl apply -f external-dns.tmp.yml && rm external-dns.tmp.yml && cd ../../

# create-ingress-controller: Install the ingress controller and scale it.
create-ingress-controller:
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/aws/deploy.yaml && \
	kubectl scale -n ingress-nginx --replicas=3 deployment ingress-nginx-controller

# create-certmanager: Create namespace and install cert-manager.
create-certmanager:
	kubectl create namespace cert-manager || true && \
	kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.6.1/cert-manager.yaml

# create-issuer: Apply issuer configuration for Let's Encrypt.
create-issuer:
	cd add-ons/certmanager && kubectl apply -f ./issuer && cd ../../

create-argocd:
	kubectl create namespace argocd
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
