# AWS infrastructure (EC2 architecture)

This Terraform root provisions a dedicated VPC in `ap-south-1`, two AZs, public/web/app/database subnets, two NAT Gateways, public and internal ALBs, ECR, two web EC2 Auto Scaling instances, two app EC2 Auto Scaling instances, a Bastion host, encrypted Multi-AZ RDS PostgreSQL, Secrets Manager, IAM instance profile, Route 53 alias (optional), and CloudWatch alarms. It does not modify either pre-existing VPC.

## Before apply

1. Install Terraform >= 1.6, AWS CLI v2, and Docker.
2. Confirm AWS identity with `aws sts get-caller-identity` and region `ap-south-1`.
3. The Bastion is accessed through Systems Manager Session Manager; no inbound SSH port is opened.
4. If using a domain, create/validate an ACM certificate in `ap-south-1`, then set `acm_certificate_arn`, `domain_name`, and `hosted_zone_id`. Without a certificate the ALB serves HTTP only. The application origin defaults automatically to the domain or ALB URL.
5. Optionally set `alarm_email` in `terraform.tfvars`; confirm the SNS email subscription after apply.
6. Set secret inputs as process environment variables, never in tfvars: `TF_VAR_jwt_secret` (32+ random bytes) and `TF_VAR_groq_api_key`; optionally `TF_VAR_db_password` (leave unset to generate one). Terraform state contains sensitive values and must be encrypted, access-controlled, and never committed. Configure a remote S3 backend with versioning, SSE-KMS and a restrictive bucket policy before team/production use.
7. Review monthly costs. Two NAT Gateways, two ALBs, four EC2 instances, Bastion, and Multi-AZ RDS are not a low-cost setup. AWS Budgets are alerts, not automatic shutdown.

## Validate and provision

```powershell
Copy-Item .\terraform.tfvars.example .\terraform.tfvars
# Edit terraform.tfvars only if you are using a custom domain / ACM certificate.
terraform init
terraform fmt -recursive
terraform validate
# Bootstrap only the two ECR repositories first, so EC2 user data can pull images on first boot.
terraform plan -target=aws_ecr_repository.backend -target=aws_ecr_repository.frontend -target=aws_ecr_lifecycle_policy.backend -target=aws_ecr_lifecycle_policy.frontend -out=ecr-bootstrap.tfplan
terraform show ecr-bootstrap.tfplan
terraform apply ecr-bootstrap.tfplan
Set-Location ../..
.\scripts\push-images-bootstrap.ps1 -Region ap-south-1
Set-Location infra/terraform
terraform plan -out=tfplan
terraform show tfplan
# Only after reviewing costs and every planned resource:
terraform apply tfplan
```

## First image deployment

The launch templates expect the `current` tag in both ECR repositories. Bootstrap ECR and push the first images before the full infrastructure apply as shown above. After the full apply creates the Auto Scaling groups, run the repository's `scripts/deploy-aws.ps1` from the project root. It builds and pushes both images, runs Alembic migration once on one app instance through SSM, then refreshes app and web containers through SSM. Wait for target groups to become healthy.

## Important limitations

- This is a production-oriented reference baseline, not a certified production deployment. It requires a live `terraform plan`, image build, security review, load test, RDS restore test, and failover exercise in your account.
- Terraform currently uses local state by default. Secure remote state before production use; do not commit `.terraform`, `*.tfstate`, `*.tfplan`, or tfvars.
- The deployment script assumes the EC2 instances are registered as SSM managed instances and have the `Project=gen-ai-labs` and `Role=app|web` tags.
- Bastion has no inbound SSH rule; use AWS Systems Manager Session Manager.
- Route 53 alias is created only when both `domain_name` and `hosted_zone_id` are supplied.
