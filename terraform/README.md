# AJS Suite — Terraform Infrastructure

Terraform configuration for deploying AJS Suite into a fresh AWS account.

## Architecture

- Dedicated VPC: 10.20.0.0/16
- Public subnet: 10.20.1.0/24
- Internet Gateway and public route table
- One Ubuntu EC2 instance
- Docker Engine and Docker Compose installed through user-data
- HTTP access on port 80
- SSH restricted to the configured administrator IPv4 CIDR
- Encrypted GP3 root volume
- EC2 IMDSv2 required
- EC2 destruction protection enabled

## Prerequisites

- Terraform >= 1.5
- AWS CLI v2
- AWS credentials configured for the target account
- An existing EC2 key pair in the target region
- Your public IPv4 address in CIDR notation

## Local validation

From the repository root:

    terraform -chdir=terraform fmt -recursive
    terraform -chdir=terraform init -backend=false
    terraform -chdir=terraform validate

## Deployment preparation

Copy the example variables file:

    cp terraform/terraform.tfvars.example terraform/terraform.tfvars

Set the actual EC2 key pair name and administrator IP address.
Never commit terraform.tfvars.

## Deployment

Deployment is intentionally not documented as an automatic step yet.
Review the AWS account, expected costs, security rules and Terraform plan
before provisioning any resources.

## Application deployment

The application is deployed separately from infrastructure provisioning.
Docker Compose configuration and environment secrets must be transferred
securely. Never commit .env or production credentials.

## Cost considerations

Public IPv4 addresses, EC2 compute, EBS storage and data transfer can incur
AWS charges. Check current regional pricing and account credits before
deployment.

## Safety

The EC2 resource has prevent_destroy enabled.
Do not disable it without reviewing the consequences.
