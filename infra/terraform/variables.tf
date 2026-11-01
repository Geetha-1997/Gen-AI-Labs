variable "aws_region" { type = string
  default = "ap-south-1" }
variable "project_name" { type = string
  default = "gen-ai-labs" }
variable "environment" { type = string
  default = "production" }
variable "vpc_cidr" { type = string
  default = "10.40.0.0/16" }
variable "availability_zones" { type = list(string)
  default = ["ap-south-1a", "ap-south-1b"] }
variable "instance_type" { type = string
  default = "t3.small" }
variable "web_desired_capacity" { type = number
  default = 2 }
variable "app_desired_capacity" { type = number
  default = 2 }
variable "web_min_size" { type = number
  default = 2 }
variable "web_max_size" { type = number
  default = 4 }
variable "app_min_size" { type = number
  default = 2 }
variable "app_max_size" { type = number
  default = 4 }
variable "db_instance_class" { type = string
  default = "db.t4g.micro" }
variable "db_name" { type = string
  default = "genailabs" }
variable "db_username" { type = string
  default = "genaiadmin" }
variable "db_password" { type = string
  default = ""
  sensitive = true
  description = "Set with TF_VAR_db_password; use a strong unique value." }
variable "jwt_secret" { type = string
  sensitive = true
  description = "Set with TF_VAR_jwt_secret; use at least 32 random bytes." }
variable "groq_api_key" { type = string
  sensitive = true
  description = "Set with TF_VAR_groq_api_key. Never commit this value." }
variable "groq_model" { type = string
  default = "openai/gpt-oss-120b" }
variable "domain_name" { type = string
  default = ""
  description = "Optional existing Route 53 hosted-zone domain, e.g. example.com. Leave empty to use ALB DNS." }
variable "hosted_zone_id" { type = string
  default = ""
  description = "Optional existing Route 53 hosted zone ID." }
variable "acm_certificate_arn" { type = string
  default = ""
  description = "Optional ACM certificate ARN in the same region for HTTPS." }
variable "enable_deletion_protection" { type = bool
  default = true }

variable "app_origin" {
  type        = string
  default     = ""
  description = "Optional exact browser origin override. Defaults to the configured domain or ALB URL."
}

variable "alarm_email" {
  type        = string
  default     = ""
  description = "Optional email address for CloudWatch alarm notifications; subscription confirmation is required."
}
