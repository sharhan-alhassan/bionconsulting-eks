# Table of Contents

- [Infrastructure Architecture](#infrastructure-architecture)
- [Resources Deployed](#resources-deployed)
- [Gitops Architecture](#gitops-architecture)
- [Future Improvements](#future-improvements)

# Infrastructure Architecture
## 🔹 VPC + EKS + Argo CD Architecture 

- VPC: Created across multiple AZs for high availability.
- Subnets: Public (for ALB) and private (for EKS nodes) spread across AZs.
- Internet Gateway: Enables internet access for public subnets.
- NAT Gateway: Lets private subnets access the internet securely.
- EKS Cluster: Runs in private subnets with managed node groups.
- ALB: Exposes services (like the frontend) to the internet.
- Security Groups: Control traffic between ALB, nodes, and pods.
- IAM Roles: Allow nodes and pods to access AWS services securely.
- ECR: Stores container images pulled by EKS workloads.
- Argo CD: Deployed in EKS to sync and manage apps via GitOps.

![Architecture Diagram](/images/arch_2.png)

# Resources Deployed

## 📌 VPC Services
- VPC
- Subnets (x2 private, x2 public)
- Internet Gateway
- NAT Gateways (x2)
- Elastic IPs for NAT (x2)
- Route Tables
  - Public
  - Private (x2)
- Route Table Associations
  - Public (x2)
  - Private (x2)
- Routes
  - Public
  - Private (x2)
- Flow Logs
  - IAM Role
  - IAM Policy
  - CloudWatch Log Group

## 📌 EKS Services

- EKS Cluster
  - Node Group (On-Demand)
  - CloudWatch Log Group
  - OIDC Provider
- IAM Roles for EKS
  - Cluster Role
  - Node Group Roles
  - Cluster Autoscaler Role
  - ExternalDNS Role
  - Karpenter Controller Role
  - Test OIDC Role
- IAM Policies
  - AmazonEKSClusterCloudWatchMetricsPolicy
  - Cluster Autoscaler Policy
  - ExternalDNS Policy
  - Karpenter Controller Policy
  - Test Policy
- IAM Policy Attachments
  - Cluster Policies
    - AmazonEKSClusterPolicy
    - AmazonEKSServicePolicy
    - AmazonEKSCloudWatchMetricsPolicy
  - Node Group Policies
    - AmazonEC2ContainerRegistryReadOnly
    - AmazonEKSWorkerNodePolicy
    - AmazonEKS_CNI_Policy
  - Karpenter Policies
    - AmazonEC2ContainerRegistryReadOnly
    - AmazonEKSWorkerNodePolicy
    - AmazonEKS_CNI_Policy
  - Other Attachments
    - Load Balancer Controller
    - Cluster Autoscaler
    - ExternalDNS
    - Test Attachments
- IAM Instance Profiles
  - Karpenter

## 📌 Helm Releases

- Ingress NGINX
- Karpenter

## 📌 Supporting Data & Configurations

- Caller Identity
- EKS Cluster Data
- IAM Policy Documents
  - Cluster Autoscaler Assume Role Policy
  - ExternalDNS Assume Role Policy
  - Karpenter Controller Assume Role Policy
  - Test OIDC Assume Role Policy
- TLS Certificate
- Kubeconfig Files
- SSM Parameter (AMI Release Version)


# Gitops Architecture

1. Code is pushed to GitHub (app + Helm/manifest files).
2. GitHub Actions triggers on push to build the app.
3. Build Docker images and push to Amazon ECR.
4. Run Grype to scan images for vulnerabilities and push to S3.
5. Update image tags in Git repo (Helm values or manifests).
6. Argo CD detects Git changes and syncs to EKS.
7. Argo CD deploys workloads using updated manifests.
8. Karpenter auto-scales nodes based on pod demands.
9. Apps run securely on EKS with proper IAM and policies.
10. Git remains the single source of truth for the entire infra.

![GitOps Diagram](/images/gitops.png)

![Argocd](/images/argocd.png)


## Chart
```sh
helm create voting-app

# Install the chart
helm install voting-app ./voting-app

# Reinstall after changes
helm upgrade --install voting-app ./voting-app

# Upgrade if already deployed
helm upgrade voting-app ./voting-app

```

## CI/CD
```sh
helm upgrade --install voting-app ./voting-app \
  --set vote.image.tag=abcd1234 \
  --set result.image.tag=abcd5678 \
  --set worker.image.tag=abcd9012

```
## Improvements
- Dynamically switch Image Tags
- Separate code Repository for Helm charts
- Separate services as separate apps and managed separately with images with separate charts

# Resources

## 📌 VPC Services
- VPC
- Subnets (x2 private, x2 public)
- Internet Gateway
- NAT Gateways (x2)
- Elastic IPs for NAT (x2)
- Route Tables
  - Public
  - Private (x2)
- Route Table Associations
  - Public (x2)
  - Private (x2)
- Routes
  - Public
  - Private (x2)
- Flow Logs
  - IAM Role
  - IAM Policy
  - CloudWatch Log Group

## 📌 EKS Services

- EKS Cluster
  - Node Group (On-Demand)
  - CloudWatch Log Group
  - OIDC Provider
- IAM Roles for EKS
  - Cluster Role
  - Node Group Roles
  - Cluster Autoscaler Role
  - ExternalDNS Role
  - Karpenter Controller Role
  - Test OIDC Role
- IAM Policies
  - AmazonEKSClusterCloudWatchMetricsPolicy
  - Cluster Autoscaler Policy
  - ExternalDNS Policy
  - Karpenter Controller Policy
  - Test Policy
- IAM Policy Attachments
  - Cluster Policies
    - AmazonEKSClusterPolicy
    - AmazonEKSServicePolicy
    - AmazonEKSCloudWatchMetricsPolicy
  - Node Group Policies
    - AmazonEC2ContainerRegistryReadOnly
    - AmazonEKSWorkerNodePolicy
    - AmazonEKS_CNI_Policy
  - Karpenter Policies
    - AmazonEC2ContainerRegistryReadOnly
    - AmazonEKSWorkerNodePolicy
    - AmazonEKS_CNI_Policy
  - Other Attachments
    - Load Balancer Controller
    - Cluster Autoscaler
    - ExternalDNS
    - Test Attachments
- IAM Instance Profiles
  - Karpenter

## 📌 Helm Releases

- Ingress NGINX
- Karpenter

## 📌 Supporting Data & Configurations

- Caller Identity
- EKS Cluster Data
- IAM Policy Documents
  - Cluster Autoscaler Assume Role Policy
  - ExternalDNS Assume Role Policy
  - Karpenter Controller Assume Role Policy
  - Test OIDC Assume Role Policy
- TLS Certificate
- Kubeconfig Files
- SSM Parameter (AMI Release Version)


# Future Improvements
- Dynamically switch Image Tags with `SEMVA` versioning 
- Separate code Repository for Helm charts
- Separate services as microservices and managed separately with helm charts