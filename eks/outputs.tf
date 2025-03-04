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