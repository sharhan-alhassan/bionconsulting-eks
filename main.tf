
terraform {
  //   required_version = "~> 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.2"
    }
    template = {
      source  = "hashicorp/template"
      version = "2.2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.36.0"
    }

  }
}

# provider "aws" {
#   assume_role {
#     role_arn     = "arn:aws:iam::130575395405:role/talent_role"
#     session_name = "sharhan-bionconsult"
#   }
# }

provider "aws" {
  region                   = "us-west-1"
  shared_credentials_files = ["~/.aws/credentials"]
  profile                  = "maoney-terraform-user"
}

module "vpc" {
  source             = "./vpc"
  name               = var.name
  environment        = var.environment
  cidr               = var.cidr
  private_subnets    = var.private_subnets
  public_subnets     = var.public_subnets
  availability_zones = var.availability_zones
  k8s_version        = var.k8s_version
  kubeconfig_path    = var.kubeconfig_path
  region             = var.region
}


module "eks" {
  source          = "./eks"
  name            = var.name
  environment     = var.environment
  region          = var.region
  k8s_version     = var.k8s_version
  private_subnets = module.vpc.private_subnets
  public_subnets  = module.vpc.public_subnets
  kubeconfig_path = var.kubeconfig_path
  vpc_id          = module.vpc.vpc_id
}


output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnets" {
  value = module.vpc.public_subnets
}

output "private_subnets" {
  value = module.vpc.private_subnets
}