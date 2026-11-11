# Outputs from terraform apply
output "public_ip" {
  description = "Automatically assigned public IPv4 address."
  value       = aws_instance.web.public_ip
}

output "domain" {
  description = "Domain name for HTTPS (Cloudflare tunnel or custom)."
  value       = "ajs-suite.${var.domain_name}"
}

output "portfolio_url" {
  description = "Public URL of the portfolio after web deployment."
  value       = "http://${aws_instance.web.public_ip}"
}

output "ssh_command" {
  description = "SSH command for connecting to the instance."
  value       = "ssh ubuntu@${aws_instance.web.public_ip}"
}

output "vpc_id" {
  description = "Application VPC ID."
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "Public subnet ID."
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "Web instance security group ID."
  value       = aws_security_group.web.id
}