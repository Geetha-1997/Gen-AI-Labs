data "aws_availability_zones" "available" { state = "available" }
data "aws_ami" "al2023" {
  most_recent = true
  owners = ["amazon"]
  filter { name = "name"
  values = ["al2023-ami-2023.*-kernel-*-x86_64"] }
  filter { name = "architecture"
  values = ["x86_64"] }
}

locals {
  name = "${var.project_name}-${var.environment}"
  azs = slice(var.availability_zones, 0, 2)
  public_cidrs = ["10.40.0.0/24", "10.40.1.0/24"]
  web_cidrs = ["10.40.10.0/24", "10.40.11.0/24"]
  app_cidrs = ["10.40.20.0/24", "10.40.21.0/24"]
  db_cidrs = ["10.40.30.0/24", "10.40.31.0/24"]
  common_tags = { Project = var.project_name, Environment = var.environment }
  app_origin = var.app_origin != "" ? var.app_origin : (var.domain_name != "" ? (var.acm_certificate_arn != "" ? "https://${var.domain_name}" : "http://${var.domain_name}") : (var.acm_certificate_arn != "" ? "https://${aws_lb.public.dns_name}" : "http://${aws_lb.public.dns_name}"))
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = { Name = "${local.name}-vpc" }
}
resource "aws_internet_gateway" "main" { vpc_id = aws_vpc.main.id
  tags = { Name = "${local.name}-igw" } }

resource "aws_subnet" "public" {
  count = 2
  vpc_id = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block = local.public_cidrs[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${local.name}-public-${count.index + 1}", Tier = "public", "kubernetes.io/role/elb" = "1" }
}
resource "aws_subnet" "web" {
  count = 2
  vpc_id = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block = local.web_cidrs[count.index]
  tags = { Name = "${local.name}-web-${count.index + 1}", Tier = "web" }
}
resource "aws_subnet" "app" {
  count = 2
  vpc_id = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block = local.app_cidrs[count.index]
  tags = { Name = "${local.name}-app-${count.index + 1}", Tier = "app" }
}
resource "aws_subnet" "db" {
  count = 2
  vpc_id = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block = local.db_cidrs[count.index]
  tags = { Name = "${local.name}-db-${count.index + 1}", Tier = "database" }
}
resource "aws_eip" "nat" { count = 2
  domain = "vpc"
  depends_on = [aws_internet_gateway.main]
  tags = { Name = "${local.name}-nat-eip-${count.index + 1}" } }
resource "aws_nat_gateway" "main" {
  count = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id = aws_subnet.public[count.index].id
  depends_on = [aws_internet_gateway.main]
  tags = { Name = "${local.name}-nat-${count.index + 1}" }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route { cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.main.id }
  tags = { Name = "${local.name}-public-rt" }
}
resource "aws_route_table_association" "public" { count = 2
  subnet_id = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id }
resource "aws_route_table" "private" {
  count = 2
  vpc_id = aws_vpc.main.id
  route { cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.main[count.index].id }
  tags = { Name = "${local.name}-private-rt-${count.index + 1}" }
}
resource "aws_route_table_association" "web" { count = 2
  subnet_id = aws_subnet.web[count.index].id
  route_table_id = aws_route_table.private[count.index].id }
resource "aws_route_table_association" "app" { count = 2
  subnet_id = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.private[count.index].id }
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "${local.name}-db-isolated-rt" }
}
resource "aws_route_table_association" "db" { count = 2
  subnet_id = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id }

resource "aws_security_group" "alb" {
  name = "${local.name}-alb-sg"
  vpc_id = aws_vpc.main.id
  description = "Public ALB ingress"
  ingress { from_port = 80
  to_port = 80
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"] }
  dynamic "ingress" { for_each = var.acm_certificate_arn == "" ? [] : [1]
  content { from_port = 443
  to_port = 443
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"] } }
  egress { from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"] }
  tags = { Name = "${local.name}-alb-sg" }
}
resource "aws_security_group" "web" {
  name = "${local.name}-web-sg"
  vpc_id = aws_vpc.main.id
  ingress { from_port = 8080
  to_port = 8080
  protocol = "tcp"
  security_groups = [aws_security_group.alb.id] }
  egress { from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"] }
  tags = { Name = "${local.name}-web-sg" }
}
resource "aws_security_group" "internal_alb" {
  name = "${local.name}-internal-alb-sg"
  vpc_id = aws_vpc.main.id
  ingress { from_port = 8000
  to_port = 8000
  protocol = "tcp"
  security_groups = [aws_security_group.web.id] }
  egress { from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"] }
  tags = { Name = "${local.name}-internal-alb-sg" }
}
resource "aws_security_group" "app" {
  name = "${local.name}-app-sg"
  vpc_id = aws_vpc.main.id
  ingress { from_port = 8000
  to_port = 8000
  protocol = "tcp"
  security_groups = [aws_security_group.internal_alb.id] }
  egress { from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"] }
  tags = { Name = "${local.name}-app-sg" }
}
resource "aws_security_group" "bastion" {
  name = "${local.name}-bastion-sg"
  vpc_id = aws_vpc.main.id
  egress { from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"] }
  tags = { Name = "${local.name}-bastion-sg" }
}
resource "aws_security_group" "db" {
  name = "${local.name}-db-sg"
  vpc_id = aws_vpc.main.id
  ingress { from_port = 5432
  to_port = 5432
  protocol = "tcp"
  security_groups = [aws_security_group.app.id] }
  tags = { Name = "${local.name}-db-sg" }
}

resource "aws_lb" "public" {
  name = "${local.name}-public"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.alb.id]
  subnets = aws_subnet.public[*].id
  enable_deletion_protection = var.enable_deletion_protection
}
resource "aws_lb_target_group" "web" {
  name = "${local.name}-web-tg"
  port = 8080
  protocol = "HTTP"
  vpc_id = aws_vpc.main.id
  health_check { path = "/"
  matcher = "200-399"
  interval = 30
  healthy_threshold = 2
  unhealthy_threshold = 3 }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.public.arn
  port = 80
  protocol = "HTTP"
  dynamic "default_action" {
    for_each = var.acm_certificate_arn == "" ? [1] : []
    content {
      type = "forward"
      target_group_arn = aws_lb_target_group.web.arn
    }
  }
  dynamic "default_action" {
    for_each = var.acm_certificate_arn != "" ? [1] : []
    content {
      type = "redirect"
      redirect {
        port = "443"
        protocol = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}
resource "aws_lb_listener" "https" {
  count = var.acm_certificate_arn == "" ? 0 : 1
  load_balancer_arn = aws_lb.public.arn
  port = 443
  protocol = "HTTPS"
  certificate_arn = var.acm_certificate_arn
  default_action { type = "forward"
  target_group_arn = aws_lb_target_group.web.arn }
}
resource "aws_lb" "internal" {
  name = "${local.name}-internal"
  internal = true
  load_balancer_type = "application"
  security_groups = [aws_security_group.internal_alb.id]
  subnets = aws_subnet.app[*].id
}
resource "aws_lb_target_group" "app" {
  name = "${local.name}-app-tg"
  port = 8000
  protocol = "HTTP"
  vpc_id = aws_vpc.main.id
  health_check { path = "/health/ready"
  matcher = "200"
  interval = 30
  healthy_threshold = 2
  unhealthy_threshold = 3 }
}
resource "aws_lb_listener" "internal" {
  load_balancer_arn = aws_lb.internal.arn
  port = 8000
  protocol = "HTTP"
  default_action { type = "forward"
  target_group_arn = aws_lb_target_group.app.arn }
}

resource "aws_ecr_repository" "backend" { name = "${var.project_name}-api"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" } }
resource "aws_ecr_repository" "frontend" { name = "${var.project_name}-web"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" } }
resource "aws_ecr_lifecycle_policy" "backend" { repository = aws_ecr_repository.backend.name
  policy = jsonencode({ rules = [{ rulePriority = 1, description = "Keep 20 images", selection = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 20 }, action = { type = "expire" } }] }) }
resource "aws_ecr_lifecycle_policy" "frontend" { repository = aws_ecr_repository.frontend.name
  policy = aws_ecr_lifecycle_policy.backend.policy }

resource "aws_secretsmanager_secret" "app" { name = "${local.name}/application"
  recovery_window_in_days = 7 }
resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({ JWT_SECRET = var.jwt_secret, GROQ_API_KEY = var.groq_api_key, GROQ_MODEL = var.groq_model })
}
resource "random_password" "db" { length = 32
  special = false }
resource "aws_secretsmanager_secret" "db" { name = "${local.name}/database"
  recovery_window_in_days = 7 }
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({ username = var.db_username, password = var.db_password != "" ? var.db_password : random_password.db.result, database = var.db_name })
}

resource "aws_db_subnet_group" "main" { name = "${local.name}-db-subnets"
  subnet_ids = aws_subnet.db[*].id
  tags = { Name = "${local.name}-db-subnets" } }
resource "aws_db_instance" "main" {
  identifier = "${local.name}-postgres"
  engine = "postgres"
  instance_class = var.db_instance_class
  allocated_storage = 30
  max_allocated_storage = 100
  storage_type = "gp3"
  storage_encrypted = true
  db_name = var.db_name
  username = var.db_username
  password = var.db_password != "" ? var.db_password : random_password.db.result
  port = 5432
  multi_az = true
  publicly_accessible = false
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  backup_retention_period = 7
  copy_tags_to_snapshot = true
  deletion_protection = var.enable_deletion_protection
  skip_final_snapshot = false
  final_snapshot_identifier = "${local.name}-final-snapshot"
  auto_minor_version_upgrade = true
  apply_immediately = false
}
resource "aws_iam_role" "app" {
  name = "${local.name}-app-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role" "web" {
  name = "${local.name}-web-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role" "bastion" {
  name = "${local.name}-bastion-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy" "app" {
  name = "${local.name}-app-policy"
  role = aws_iam_role.app.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"], Resource = [aws_ecr_repository.backend.arn] },
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [aws_secretsmanager_secret.app.arn, aws_secretsmanager_secret.db.arn] },
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"], Resource = ["${aws_cloudwatch_log_group.app.arn}:*"] }
  ] })
}
resource "aws_iam_role_policy" "web" {
  name = "${local.name}-web-policy"
  role = aws_iam_role.web.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"], Resource = [aws_ecr_repository.frontend.arn] },
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"], Resource = ["${aws_cloudwatch_log_group.app.arn}:*"] }
  ] })
}
resource "aws_iam_role_policy_attachment" "ssm_app" { role = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" }
resource "aws_iam_role_policy_attachment" "ssm_web" { role = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" }
resource "aws_iam_role_policy_attachment" "ssm_bastion" { role = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" }
resource "aws_iam_instance_profile" "app" { name = "${local.name}-app-profile"
  role = aws_iam_role.app.name }
resource "aws_iam_instance_profile" "web" { name = "${local.name}-web-profile"
  role = aws_iam_role.web.name }
resource "aws_iam_instance_profile" "bastion" { name = "${local.name}-bastion-profile"
  role = aws_iam_role.bastion.name }

resource "aws_launch_template" "app" {
  name_prefix = "${local.name}-app-"
  image_id = data.aws_ami.al2023.id
  instance_type = var.instance_type
  iam_instance_profile { name = aws_iam_instance_profile.app.name }
  vpc_security_group_ids = [aws_security_group.app.id]
  metadata_options { http_tokens = "required"
  http_endpoint = "enabled" }
  block_device_mappings { device_name = "/dev/xvda"
  ebs { volume_size = 20
  volume_type = "gp3"
  encrypted = true
  delete_on_termination = true } }
  user_data = base64encode(templatefile("${path.module}/userdata-app.sh.tftpl", {
    region = var.aws_region,
    backend_repo = aws_ecr_repository.backend.repository_url, app_secret = aws_secretsmanager_secret.app.arn,
    db_secret = aws_secretsmanager_secret.db.arn, db_host = aws_db_instance.main.address, db_name = var.db_name,
    db_user = var.db_username, image_tag = "current", app_origin = local.app_origin,
    log_group = aws_cloudwatch_log_group.app.name
  }))
  tag_specifications { resource_type = "instance"
  tags = { Name = "${local.name}-app"
  Role = "app" } }
  depends_on = [aws_db_instance.main, aws_secretsmanager_secret_version.app, aws_secretsmanager_secret_version.db, aws_iam_role_policy.app, aws_iam_role_policy_attachment.ssm_app]
}
resource "aws_autoscaling_group" "app" {
  name = "${local.name}-app-asg"
  min_size = var.app_min_size
  max_size = var.app_max_size
  desired_capacity = var.app_desired_capacity
  vpc_zone_identifier = aws_subnet.app[*].id
  target_group_arns = [aws_lb_target_group.app.arn]
  health_check_type = "ELB"
  health_check_grace_period = 600
  launch_template { id = aws_launch_template.app.id
  version = "$Latest" }
  tag { key = "Name"
  value = "${local.name}-app"
  propagate_at_launch = true }
  tag { key = "Project"
  value = var.project_name
  propagate_at_launch = true }
}

resource "aws_autoscaling_policy" "app_cpu" {
  name                   = "${local.name}-app-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification { predefined_metric_type = "ASGAverageCPUUtilization" }
    target_value = 50.0
  }
}

resource "aws_launch_template" "web" {
  name_prefix = "${local.name}-web-"
  image_id = data.aws_ami.al2023.id
  instance_type = var.instance_type
  iam_instance_profile { name = aws_iam_instance_profile.web.name }
  vpc_security_group_ids = [aws_security_group.web.id]
  metadata_options { http_tokens = "required"
  http_endpoint = "enabled" }
  block_device_mappings { device_name = "/dev/xvda"
  ebs { volume_size = 20
  volume_type = "gp3"
  encrypted = true
  delete_on_termination = true } }
  user_data = base64encode(templatefile("${path.module}/userdata-web.sh.tftpl", {
    region = var.aws_region,
    frontend_repo = aws_ecr_repository.frontend.repository_url, internal_alb = aws_lb.internal.dns_name,
    image_tag = "current", log_group = aws_cloudwatch_log_group.app.name
  }))
  tag_specifications { resource_type = "instance"
  tags = { Name = "${local.name}-web"
  Role = "web" } }
  depends_on = [aws_iam_role_policy.web, aws_iam_role_policy_attachment.ssm_web]
}
resource "aws_autoscaling_group" "web" {
  name = "${local.name}-web-asg"
  min_size = var.web_min_size
  max_size = var.web_max_size
  desired_capacity = var.web_desired_capacity
  vpc_zone_identifier = aws_subnet.web[*].id
  target_group_arns = [aws_lb_target_group.web.arn]
  health_check_type = "ELB"
  health_check_grace_period = 600
  launch_template { id = aws_launch_template.web.id
  version = "$Latest" }
  tag { key = "Name"
  value = "${local.name}-web"
  propagate_at_launch = true }
  tag { key = "Project"
  value = var.project_name
  propagate_at_launch = true }
}

resource "aws_autoscaling_policy" "web_cpu" {
  name                   = "${local.name}-web-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification { predefined_metric_type = "ASGAverageCPUUtilization" }
    target_value = 50.0
  }
}

resource "aws_instance" "bastion" {
  ami = data.aws_ami.al2023.id
  instance_type = "t3.micro"
  subnet_id = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile = aws_iam_instance_profile.bastion.name
  associate_public_ip_address = true
  metadata_options { http_tokens = "required" }
  root_block_device { volume_size = 10
  volume_type = "gp3"
  encrypted = true }
  tags = { Name = "${local.name}-bastion"
  Role = "bastion" }
  depends_on = [aws_iam_role_policy_attachment.ssm_bastion]
}

resource "aws_cloudwatch_log_group" "app" { name = "/${var.project_name}/${var.environment}"
  retention_in_days = 30 }
resource "aws_sns_topic" "alerts" {
  count = var.alarm_email == "" ? 0 : 1
  name  = "${local.name}-alerts"
}
resource "aws_sns_topic_subscription" "alerts_email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name = "${local.name}-alb-5xx"
  namespace = "AWS/ApplicationELB"
  metric_name = "HTTPCode_ELB_5XX_Count"
  statistic = "Sum"
  period = 300
  evaluation_periods = 2
  threshold = 10
  comparison_operator = "GreaterThanThreshold"
  dimensions = { LoadBalancer = aws_lb.public.arn_suffix }
  treat_missing_data = "notBreaching"
  alarm_actions = var.alarm_email == "" ? [] : [aws_sns_topic.alerts[0].arn]
}
resource "aws_cloudwatch_metric_alarm" "unhealthy_web" {
  alarm_name = "${local.name}-unhealthy-web-targets"
  namespace = "AWS/ApplicationELB"
  metric_name = "UnHealthyHostCount"
  statistic = "Maximum"
  period = 60
  evaluation_periods = 2
  threshold = 0
  comparison_operator = "GreaterThanThreshold"
  dimensions = { TargetGroup = aws_lb_target_group.web.arn_suffix, LoadBalancer = aws_lb.public.arn_suffix }
  treat_missing_data = "notBreaching"
  alarm_actions = var.alarm_email == "" ? [] : [aws_sns_topic.alerts[0].arn]
}
resource "aws_cloudwatch_metric_alarm" "unhealthy_app" {
  alarm_name = "${local.name}-unhealthy-app-targets"
  namespace = "AWS/ApplicationELB"
  metric_name = "UnHealthyHostCount"
  statistic = "Maximum"
  period = 60
  evaluation_periods = 2
  threshold = 0
  comparison_operator = "GreaterThanThreshold"
  dimensions = { TargetGroup = aws_lb_target_group.app.arn_suffix, LoadBalancer = aws_lb.internal.arn_suffix }
  treat_missing_data = "notBreaching"
  alarm_actions = var.alarm_email == "" ? [] : [aws_sns_topic.alerts[0].arn]
}

resource "aws_route53_record" "app" {
  count = var.domain_name != "" && var.hosted_zone_id != "" ? 1 : 0
  zone_id = var.hosted_zone_id
  name = var.domain_name
  type = "A"
  alias { name = aws_lb.public.dns_name
  zone_id = aws_lb.public.zone_id
  evaluate_target_health = true }
}

data "aws_caller_identity" "current" {}
