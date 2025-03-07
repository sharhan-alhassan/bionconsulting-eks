

terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
  }
}
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  // token                  = data.aws_eks_cluster_auth.cluster.token

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.core_src.id]
  }
}

data "aws_eks_cluster" "cluster" {
  name = aws_eks_cluster.core_src.id
}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.core_src.id
}

// Remove For Cost Savings
// Cloudwatch metrics Policy and attachement
resource "aws_iam_policy" "AmazonEKSClusterCloudWatchMetricsPolicy" {
  name   = "${var.name}-${var.environment}-AmazonEKSClusterCloudWatchMetricsPolicy"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "cloudwatch:PutMetricData",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogStreams"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "AmazonEKSCloudWatchMetricsPolicy" {
  policy_arn = aws_iam_policy.AmazonEKSClusterCloudWatchMetricsPolicy.arn
  role       = aws_iam_role.eks_cluster_role.name
}

// Cloudwatch log group
// Comment in order to run other tf scripts else it'll throw error it already exists in AWS Console
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.name}-${var.environment}/cluster"
  retention_in_days = 14
  tags = {
    Name        = "${var.name}-${var.environment}-eks-cloudwatch-log-group"
    Environment = var.environment
  }
}


// IAM role with AmazonEKSClusterPolicy to manage instance group
// eks
resource "aws_iam_role" "eks_cluster_role" {
  name                  = "${var.name}-${var.environment}-eks-cluster-role"
  force_detach_policies = true

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "eks.amazonaws.com"
          ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_eks_cluster" "core_src" {
  name     = "${var.name}-${var.environment}"
  role_arn = aws_iam_role.eks_cluster_role.arn

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_config {
    # subnet_ids = concat(var.public_subnets.*.id, var.private_subnets.*.id)
    subnet_ids = var.private_subnets
  }

  timeouts {
    delete = "30m"
  }

  version = var.k8s_version

  depends_on = [
    aws_cloudwatch_log_group.eks_cluster,
    aws_iam_role_policy_attachment.AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.AmazonEKSServicePolicy
  ]
}


// Nodes: eks_node_group_role
resource "aws_iam_role" "eks_node_group_role" {
  name                  = "${var.name}-${var.environment}-eks-node-group-role"
  force_detach_policies = true

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ec2.amazonaws.com"
          ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group_role.name
}

// Update Node group versions
data "aws_ssm_parameter" "core_src_ami_release_version" {
  name = "/aws/service/eks/optimized-ami/${aws_eks_cluster.core_src.version}/amazon-linux-2/recommended/release_version"
#   name = "/aws/service/eks/optimized-ami/${aws_eks_cluster.core_src.version}/bottlerocket/recommended/image_id"
#   name = "/aws/service/bottlerocket/aws-k8s-${aws_eks_cluster.core_src.version}/x86_64/latest/image_id"
}


resource "aws_security_group" "eks_node_group_sg" {
  name        = "${var.name}-${var.environment}-eks-node-group-sg"
  description = "Custom SG for EKS nodes"
  vpc_id      = var.vpc_id

  // Allow node-to-node communication (within the same SG)
  ingress {
    description = "Allow node-to-node communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  // Allow control plane to webhook port (9443)
  ingress {
    description                   = "Allow access from control plane to webhook port"
    from_port                     = 9443
    to_port                       = 9443
    protocol                      = "tcp"
    security_groups               = [aws_eks_cluster.core_src.vpc_config[0].cluster_security_group_id]
  }

  // Allow control plane to nodes (API server, kubelet)
  ingress {
    description                   = "Allow control plane to nodes (1025-65535)"
    from_port                     = 1025
    to_port                       = 65535
    protocol                      = "tcp"
    security_groups               = [aws_eks_cluster.core_src.vpc_config[0].cluster_security_group_id]
  }

  // Allow control plane to nodes on 443 (for webhooks, etc.)
  ingress {
    description                   = "Allow control plane to nodes (443)"
    from_port                     = 443
    to_port                       = 443
    protocol                      = "tcp"
    security_groups               = [aws_eks_cluster.core_src.vpc_config[0].cluster_security_group_id]
  }

  // Allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-${var.environment}-eks-node-group-sg"
  }
}


# resource "aws_launch_template" "eks_node_group_lt" {
#   name_prefix   = "${var.name}-${var.environment}-eks-node-group-lt-"

#   block_device_mappings {
#     device_name = "/dev/xvda"
#     ebs {
#       volume_size = 50
#       volume_type = "gp3"
#     }
#   }

#   network_interfaces {
#     security_groups = [aws_security_group.eks_node_group_sg.id]
#   }

#   tag_specifications {
#     resource_type = "instance"
#     tags = {
#       Name = "${var.name}-${var.environment}-eks-node"
#     }
#   }

#   # lifecycle {
#   #   create_before_destroy = true
#   # }
# }


//Node group -- on_demand for production workload
resource "aws_eks_node_group" "on_demand" {
  cluster_name    = aws_eks_cluster.core_src.name
  node_group_name = "${var.name}-${var.environment}-private-nodes-production"
  node_role_arn   = aws_iam_role.eks_node_group_role.arn
  subnet_ids      = var.private_subnets


  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 1
  }

  capacity_type  = "ON_DEMAND"
  instance_types = ["c5.2xlarge"]
  disk_size   = "50"

  version = aws_eks_cluster.core_src.version
  release_version = nonsensitive(data.aws_ssm_parameter.core_src_ami_release_version.value)

  # launch_template {
  #   id      = aws_launch_template.eks_node_group_lt.id
  #   version = "$Latest"
  # }

  update_config {
    max_unavailable = 1
  }

  // Enable autoscaling through Node Group
  // Optional: Allow external changes without Terraform plan difference
  # lifecycle {
  #   ignore_changes = [scaling_config[0].desired_size]
  # }

  tags = {
    Name        = "${var.name}-${var.environment}-eks-node-group-production"
    Environment = var.environment
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
  ]
}


// iam-oidc permissions to service accounts used by pods
data "tls_certificate" "eks" {
  url = aws_eks_cluster.core_src.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "core_src" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.core_src.identity[0].oidc[0].issuer
}


// Test iam provider (iam-test.tf //separate file)
data "aws_iam_policy_document" "test_oidc_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.core_src.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:default:aws-test"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.core_src.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "test_oidc" {
  assume_role_policy = data.aws_iam_policy_document.test_oidc_assume_role_policy.json
  name               = "${var.name}-${var.environment}-test-oidc"
}

resource "aws_iam_policy" "test-policy" {
  name = "${var.name}-${var.environment}-test-policy"

  policy = jsonencode({
    Statement = [{
      Action = [
        "s3:ListAllMyBuckets",
        "s3:GetBucketLocation"
      ]
      Effect   = "Allow"
      Resource = "arn:aws:s3:::*"
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "test_attach" {
  role       = aws_iam_role.test_oidc.name
  policy_arn = aws_iam_policy.test-policy.arn
}

// Creating a separate kubeconfig file
data "template_file" "kubeconfig" {
  template = file("${path.module}/templates/kubeconfig.tpl")

  vars = {
    kubeconfig_name     = "eks_${aws_eks_cluster.core_src.name}"
    clustername         = aws_eks_cluster.core_src.name
    endpoint            = data.aws_eks_cluster.cluster.endpoint
    cluster_auth_base64 = data.aws_eks_cluster.cluster.certificate_authority[0].data
  }
}

resource "local_file" "kubeconfig" {
  content  = data.template_file.kubeconfig.rendered
  filename = pathexpand("${var.kubeconfig_path}/${var.name}-${var.environment}-config")
}


// IAM-AUTOSCALER role & policy
data "aws_iam_policy_document" "eks_cluster_autoscaler_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.core_src.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.core_src.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "eks_cluster_autoscaler" {
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_autoscaler_assume_role_policy.json
  name               = "${var.name}-${var.environment}-eks-cluster-autoscaler"
}

resource "aws_iam_policy" "eks_cluster_autoscaler" {
  name = "${var.name}-${var.environment}-eks-cluster-autoscaler"

  policy = jsonencode({
    Statement = [{
      Action = [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_autoscaler_attach" {
  role       = aws_iam_role.eks_cluster_autoscaler.name
  policy_arn = aws_iam_policy.eks_cluster_autoscaler.arn
}

output "eks_cluster_autoscaler_arn" {
  value = aws_iam_role.eks_cluster_autoscaler.arn
}


// External DNS IAM Role
data "aws_iam_policy_document" "externaldns_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.core_src.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:external-dns:external-dns"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.core_src.arn]
      type        = "Federated"
    }
  }
}

data "aws_iam_policy_document" "externaldns_role" {
  statement {
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:GetHostedZone"]
    resources = ["*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }

}

resource "aws_iam_role" "externaldns_route53" {
  assume_role_policy = data.aws_iam_policy_document.externaldns_assume.json
  name               = "${var.name}-${var.environment}-externaldns_route53"
  // inline_policy {
    // name   = "${var.name}-${var.environment}-externaldns_role"
    // policy = data.aws_iam_policy_document.externaldns_role.json
  // }

}

resource "aws_iam_policy" "externaldns_role" {
  name        = "${var.name}-${var.environment}-externaldns_role"
  description = "Policy for ExternalDNS to manage Route 53"
  policy      = data.aws_iam_policy_document.externaldns_role.json
}

resource "aws_iam_role_policy_attachment" "externaldns_policy_attachment" {
  role       = aws_iam_role.externaldns_route53.name
  policy_arn = aws_iam_policy.externaldns_role.arn
}


data "aws_caller_identity" "current" {}

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

// NEW!! -- KARPENTER
// Nodes: eks_node_group_role_karpenter for Karpenter
resource "aws_iam_role" "eks_node_group_role_karpenter" {
  name                  = "${var.name}-${var.environment}-eks-node-group-role-karpenter"
  force_detach_policies = true

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ec2.amazonaws.com"
          ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy_Karepenter" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group_role_karpenter.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy_Karepenter" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group_role_karpenter.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly_Karepenter" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group_role_karpenter.name
}


data "aws_iam_policy_document" "karpenter_controller_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.core_src.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:karpenter:karpenter"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.core_src.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume_role_policy.json
  name               = "karpenter-controller-${var.name}-${var.environment}"
}

resource "aws_iam_policy" "karpenter_controller" {
  policy = file("${path.module}/policies/controller-trust-policy.json")
  name   = "KarpenterController-${var.name}-${var.environment}"
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller_attach" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

resource "aws_iam_instance_profile" "karpenter" {
  name = "KarpenterNodeInstanceProfile_${var.name}-${var.environment}"
  role = aws_iam_role.eks_node_group_role_karpenter.name
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.core_src.id]
      command     = "aws"
    }
  }
}

resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "https://charts.karpenter.sh"
  chart      = "karpenter"
  version    = "v0.16.3"

  values = [
    yamlencode({
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = "${aws_iam_role.karpenter_controller.arn}"
        }
      }
      clusterName            = "${var.name}-${var.environment}"
      clusterEndpoint        = "${data.aws_eks_cluster.cluster.endpoint}"
      aws = {
        defaultInstanceProfile = "${aws_iam_instance_profile.karpenter.name}"
      }
    })
  ]

  depends_on = [
    aws_eks_node_group.on_demand
  ]
}

########################################## Nginx Ingress Controller ##########################################
# resource "helm_release" "ingress_nginx" {
#   namespace  = "ingress-nginx"
#   create_namespace = true

#   name       = "ingress-nginx"
#   repository = "https://kubernetes.github.io/ingress-nginx"
#   chart      = "ingress-nginx"
#   version    = "4.12.0"       # HELM CHART VES

#   values = [
#     yamlencode({
#       controller = {
#         replicaCount = 3
#         service = {
#           annotations = {
#             "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
#             "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
#             "service.beta.kubernetes.io/aws-load-balancer-backend-protocol" = "tcp"
#           }
#         }
#       }
#     })
#   ]

#   depends_on = [
#     aws_eks_node_group.on_demand
#   ]

# }




# ALB Controller IAM Policies
resource "aws_iam_policy" "alb_controller_policy" {
  name        = "AWSLoadBalancerControllerIAMPolicy-${var.name}-${var.environment}"
  policy      = file("${path.module}/policies/iam_policy.json")
}

resource "aws_iam_policy" "alb_controller_additional_policy" {
  name        = "AWSLoadBalancerControllerAdditionalIAMPolicy-${var.name}-${var.environment}"
  policy      = file("${path.module}/policies/iam_policy_v1_to_v2_additional.json")
}

resource "aws_iam_role" "alb_controller_role" {
  name = "AmazonEKSLoadBalancerControllerRole-${var.name}-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "${aws_iam_openid_connect_provider.core_src.arn}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace("${aws_eks_cluster.core_src.identity[0].oidc[0].issuer}", "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach_alb_policy" {
  role       = aws_iam_role.alb_controller_role.name
  policy_arn = aws_iam_policy.alb_controller_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_additional_policy" {
  role       = aws_iam_role.alb_controller_role.name
  policy_arn = aws_iam_policy.alb_controller_additional_policy.arn
}

resource "kubernetes_service_account" "alb_controller_sa" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller_role.arn
    }
  }
}

resource "aws_security_group" "alb_sg" {
  name        = "alb-sg-${var.name}-${var.environment}"
  description = "Security group for ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg"
    ENV = "${var.name}-${var.environment}"
  }
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.11.0" 

  set {
    name  = "vpcId"
    value = "${var.vpc_id}"
  }

  set {
    name  = "autoDiscoverAwsRegion"
    value = "true"
  }

  set {
    name  = "autoDiscoverAwsVpcID"
    value = "true"
  }
  set {
    name  = "clusterName"
    value = aws_eks_cluster.core_src.name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "${kubernetes_service_account.alb_controller_sa.metadata[0].name}"
  }

  set {
    name  = "createCRD"
    value = "true"
  }

  depends_on = [
    kubernetes_service_account.alb_controller_sa
  ]
}

