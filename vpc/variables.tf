variable "environment" {
  description = "The environment this would be deployed in"
  type = string
}

variable "name" {
  description = "the name of your stack, e.g. \"demo\""
  type = string
}

variable "region" {
  description = "the AWS region in which resources are created, you must set the availability_zones variable as well if you define this value to something other than the default"
  type = string
}

variable "availability_zones" {
  description = "a comma-separated list of availability zones, defaults to all AZ of the region, if set to something other than the defaults, both private_subnets and public_subnets have to be defined as well"
  type =  list(string)
}

variable "cidr" {
  description = "The CIDR block for the VPC."
  type = string
}

variable "private_subnets" {
  description = "a list of CIDRs for private subnets in your VPC, must be set if the cidr variable is defined, needs to have as many elements as there are availability zones"
  type        = list(string)
}

variable "public_subnets" {
  description = "a list of CIDRs for public subnets in your VPC, must be set if the cidr variable is defined, needs to have as many elements as there are availability zones"
  type =  list(string)
}

variable "kubeconfig_path" {
  description = "Path where the config file for kubectl should be written to"
  type =  string
}

variable "k8s_version" {
  description = "kubernetes version"
  type = string
}