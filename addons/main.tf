
# resource "aws_route53_zone" "this" {
#   name = var.zone_name
# }

# resource "helm_release" "external_dns" {
#   name       = "external-dns"
#   namespace  = "external-dns"
#   repository = "https://kubernetes-sigs.github.io/external-dns/"
#   chart      = "external-dns"
#   version    = "1.12.2"

#   set {
#     name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
#     value = var.external_dns_role
#   }
#   set {
#     name  = "domainFilters[0]"
#     value = var.domain_filter
#   }
#   set {
#     name  = "policy"
#     value = "sync"
#   }
# }


# resource "helm_release" "cluster_autoscaler" {
#   name       = "cluster-autoscaler"
#   namespace  = "kube-system"
#   repository = "https://kubernetes.github.io/autoscaler"
#   chart      = "cluster-autoscaler"
#   version    = "9.29.0"

#   set {
#     name  = "awsRegion"
#     value = var.region
#   }
#   set {
#     name  = "autoDiscovery.clusterName"
#     value = var.cluster_name
#   }
#   set {
#     name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
#     value = var.cluster_autoscaler_role
#   }
# }


# resource "helm_release" "cert_manager" {
#   name       = "cert-manager"
#   namespace  = "cert-manager"
#   repository = "https://charts.jetstack.io"
#   chart      = "cert-manager"
#   version    = "1.6.1"
# }
