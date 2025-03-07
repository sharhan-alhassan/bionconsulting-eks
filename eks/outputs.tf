output "test_policy_arn" {
  value = aws_iam_role.test_oidc.arn
}

output "kubectl_config" {
  description = "Path to new kubectl config file"
  value       = pathexpand("${var.kubeconfig_path}/${terraform.workspace}-config")
}

output "cluster_id" {
  description = "ID of the created cluster"
  value       = aws_eks_cluster.core_src.id
}

output "eks_node_group_security_group_id" {
  description = "Security Group ID of the custom EKS node group"
  value       = aws_security_group.eks_node_group_sg.id
}

output "eks_node_group_name" {
  description = "Name of the EKS node group"
  value       = aws_eks_node_group.on_demand.node_group_name
}

output "aws_alb_security_group_id" {
  description = "Security Group ID of the ALB"
  value = aws_security_group.alb_sg.id
}