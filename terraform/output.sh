#!/bin/bash
# Helper script to source Terraform outputs before running ansible.
# Usage: source terraform/output.sh
#   export TF_PUBLIC_IP=$(terraform output -raw public_ip)
#   export TF_DOMAIN=$(terraform output -raw domain)
#
# Run from the terraform directory:
#   cd terraform && source output.sh

echo "export TF_PUBLIC_IP=$(terraform output -raw public_ip)"
echo "export TF_DOMAIN=$(terraform output -raw domain)"