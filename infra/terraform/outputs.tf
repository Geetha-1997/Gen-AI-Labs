output "region" { value = var.aws_region }
output "vpc_id" { value = aws_vpc.main.id }
output "public_alb_dns" { value = aws_lb.public.dns_name }
output "public_alb_url" { value = var.acm_certificate_arn == "" ? "http://${aws_lb.public.dns_name}" : "https://${aws_lb.public.dns_name}" }
output "internal_alb_dns" { value = aws_lb.internal.dns_name }
output "backend_ecr_url" { value = aws_ecr_repository.backend.repository_url }
output "frontend_ecr_url" { value = aws_ecr_repository.frontend.repository_url }
output "rds_endpoint" { value = aws_db_instance.main.address }
output "bastion_public_ip" { value = aws_instance.bastion.public_ip }
output "web_asg_name" { value = aws_autoscaling_group.web.name }
output "app_asg_name" { value = aws_autoscaling_group.app.name }
output "database_secret_arn" { value = aws_secretsmanager_secret.db.arn }
output "application_secret_arn" { value = aws_secretsmanager_secret.app.arn }

output "public_alb_zone_id" { value = aws_lb.public.zone_id }
output "app_origin" { value = local.app_origin }
output "web_target_group_arn" { value = aws_lb_target_group.web.arn }
output "app_target_group_arn" { value = aws_lb_target_group.app.arn }
