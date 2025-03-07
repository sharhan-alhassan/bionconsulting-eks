output "vpc_id" {
  value = aws_vpc.core_src.id
}

output "public_subnets" {
  value = [for subnet in aws_subnet.public : subnet.id]

}

output "private_subnets" {
  value = [for subnet in aws_subnet.private : subnet.id]
}
