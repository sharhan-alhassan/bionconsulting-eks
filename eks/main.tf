
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
  retention_in_days = 7

#   lifecycle {
#     prevent_destroy = true
#   }

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

//Node group -- on_demand for production workload
resource "aws_eks_node_group" "on_demand" {
  cluster_name    = aws_eks_cluster.core_src.name
  node_group_name = "${var.name}-${var.environment}-private-nodes-production"
  node_role_arn   = aws_iam_role.eks_node_group_role.arn
  subnet_ids      = var.private_subnets


  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  capacity_type  = "ON_DEMAND"
  instance_types = ["c5.2xlarge"]
  disk_size   = "50"

  version = aws_eks_cluster.core_src.version
  release_version = nonsensitive(data.aws_ssm_parameter.core_src_ami_release_version.value)


  update_config {
    max_unavailable = 1
  }

    #   taint {
    #     key    = "workload"
    #     value  = "production"
    #     effect = "NO_SCHEDULE"
    #   }

    #   labels = {
    #     node-type = "on-demand"
    #   }

  // Enable autoscaling through Node Group
  // Optional: Allow external changes without Terraform plan difference
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

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

// output "test_policy_arn" {
//   value = aws_iam_role.test_oidc.arn
// }

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

# data "aws_iam_instance_profile" "karpenter" {
#   name = "daba-qa-eks-node-group-role-karpenter"
# }

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

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter_controller.arn
  }

  set {
    name  = "clusterName"
    value = "${var.name}-${var.environment}"
  }

  set {
    name  = "clusterEndpoint"
    value = data.aws_eks_cluster.cluster.endpoint
  }

  set {
    name  = "aws.defaultInstanceProfile"
    value = aws_iam_instance_profile.karpenter.name
  }

  depends_on = [
    aws_eks_node_group.on_demand
  ]
}
