terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "eu-central-1"
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
data "aws_ami" "amzn2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
# 1. ALB Security Group: Open to the world (HTTP 80)
resource "aws_security_group" "lb_sg" {
  name        = "cosmin-prod-lb-sg"
  description = "Allow HTTP to Load Balancer"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 2. EC2 Security Group: Allows traffic ONLY from ALB + SSH from everywhere
resource "aws_security_group" "ec2_sg" {
  name        = "cosmin-prod-ec2-sg"
  description = "Allow traffic from ALB and SSH"
  vpc_id      = data.aws_vpc.default.id

  # HTTP: Allow ONLY from the Load Balancer
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id] 
  }

  # SSH: Allow for deployment (In real prod, i should restrict this to GitHub IPs or VPN)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------------------------------------------------------
# Load Balancer & Target Groups
# -----------------------------------------------------------------------------
resource "aws_lb" "app" {
  name               = "cosmin-prod-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "blue" {
  name     = "cosmin-tg-blue"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  health_check {
    path                = "/version.txt"
    matcher             = "200"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "green" {
  name     = "cosmin-tg-green"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  health_check {
    path                = "/version.txt"
    matcher             = "200"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Listener: Defaults to BLUE initially
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.app.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

# -----------------------------------------------------------------------------
# EC2 Instances (Blue & Green)
# -----------------------------------------------------------------------------
resource "aws_key_pair" "prod_key" {
  key_name   = "cosmin-prod-key"
  public_key = file(pathexpand("~/.ssh/cosmin-ec2.pub"))
}

# Shared User Data script
locals {
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y nginx unzip
    systemctl enable nginx --now
    # Default placeholder content
    echo "<h1>Waiting for Deployment...</h1>" > /usr/share/nginx/html/index.html
    echo "initial_version" > /usr/share/nginx/html/version.txt
    chown -R ec2-user:ec2-user /usr/share/nginx/html
  EOF
}

resource "aws_instance" "blue" {
  ami                    = data.aws_ami.amzn2.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.prod_key.key_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id              = element(data.aws_subnets.default.ids, 0)
  user_data              = local.user_data
  tags = { Name = "Prod-Blue", Color = "blue" }
}

resource "aws_instance" "green" {
  ami                    = data.aws_ami.amzn2.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.prod_key.key_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id              = element(data.aws_subnets.default.ids, 1) # Put in different AZ if possible
  user_data              = local.user_data
  tags = { Name = "Prod-Green", Color = "green" }
}

# -----------------------------------------------------------------------------
# Attachments
# -----------------------------------------------------------------------------
resource "aws_lb_target_group_attachment" "blue" {
  target_group_arn = aws_lb_target_group.blue.arn
  target_id        = aws_instance.blue.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "green" {
  target_group_arn = aws_lb_target_group.green.arn
  target_id        = aws_instance.green.id
  port             = 80
}