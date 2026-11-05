variable "project_name" {
  description = "Project name used in AWS resource tags."
  type        = string
  default     = "ajs-suite"
}

variable "aws_region" {
  description = "AWS deployment region."
  type        = string
  default     = "ap-south-1"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Existing EC2 key pair name in the target AWS account."
  type        = string
}

variable "ssh_cidr" {
  description = "Your public IPv4 address in CIDR notation, e.g. 203.0.113.10/32."
  type        = string

  validation {
    condition     = can(cidrhost(var.ssh_cidr, 0)) && var.ssh_cidr != "0.0.0.0/0"
    error_message = "Provide a valid, restricted IPv4 CIDR. Do not expose SSH to the entire internet."
  }
}

variable "root_volume_size" {
  description = "EC2 root disk size in GiB."
  type        = number
  default     = 12

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 30
    error_message = "Root volume size must be between 8 and 30 GiB."
  }
}

variable "vpc_cidr" {
  description = "CIDR range for the application VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR range for the public subnet."
  type        = string
  default     = "10.20.1.0/24"
}
