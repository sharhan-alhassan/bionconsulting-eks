#!/bin/bash

ENV=$1

# Define backend and variable file locations
BACKEND_DIR="./backends"
VARS_DIR="./environments"
BACKEND_FILE="$BACKEND_DIR/backend-$ENV.tf"
VARS_FILE="$VARS_DIR/$ENV.tfvars"

# Validate input
if [[ "$ENV" != "staging" && "$ENV" != "combined" && "$ENV" != "production" ]]; then
    echo "Usage: ./deploy.sh [staging|combined|production]"
    exit 1
fi

echo "Deploying to $ENV environment..."

# Copy the correct backend file to the working directory
echo "Copying ${BACKEND_FILE} to backend.tf..."
cp $BACKEND_FILE backend.tf

# Initialize Terraform
echo "About to Initialize..."
terraform init

# Select or create the workspace
terraform workspace select $ENV || terraform workspace new $ENV

# Format Terraform with the appropriate variable file
terraform fmt 

# Validate Terraform with the appropriate variable file
terraform validate

# Plan Terraform with the appropriate variable file
terraform plan -var-file=$VARS_FILE -out=tfplan

# # Apply Terraform with the appropriate variable file
terraform apply -var-file=$VARS_FILE -auto-approve

