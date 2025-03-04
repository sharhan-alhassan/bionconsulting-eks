ENV ?= staging
BACKEND_DIR = ./backends
VARS_DIR = ./environments
BACKEND_FILE = $(BACKEND_DIR)/backend-$(ENV).tf
VARS_FILE = $(VARS_DIR)/$(ENV).tfvars

.PHONY: init workspace fmt validate plan apply clean

## Initialize Terraform and copy backend
init:
	@if [ "$(ENV)" != "staging" ] && [ "$(ENV)" != "combined" ] && [ "$(ENV)" != "production" ]; then \
		echo "Usage: make [init|workspace|plan|apply] ENV=[staging|combined|production]"; \
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

## Format and validate
fmt:
	@terraform fmt
	@terraform validate

## Terraform Plan
plan:
	@terraform plan -var-file=$(VARS_FILE) -out=tfplan

## Terraform Apply
apply:
	@terraform apply -var-file=$(VARS_FILE) -auto-approve

## Terraform Destroy
apply:
	@terraform destroy -var-file=$(VARS_FILE) -auto-approve

## Clean backend file (optional)
clean:
	rm -f backend.tf