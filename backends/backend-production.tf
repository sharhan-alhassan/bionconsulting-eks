
terraform {
  backend "s3" {
    bucket         = "bioncon-production-eks-tfstate-bucket"
    key            = "eks/production/terraform.tfstate"
    region         = "us-west-1"
    encrypt        = true
    use_lockfile = true
  }
}
