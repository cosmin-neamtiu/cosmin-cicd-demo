    terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "eu-central-1"
}

data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# PROD Specific Security Group
resource "aws_security_group" "prod_web" {
  name        = "cosmin-prod-web-sg"
  description = "Allow HTTP and SSH for PROD"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }
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

data "aws_ami" "amzn2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Reuse the same public key for simplicity, or create a new one
resource "aws_key_pair" "prod_key" {
  key_name   = "cosmin-prod-key"
  public_key = file(pathexpand("~/.ssh/cosmin-ec2.pub"))
}

resource "aws_instance" "prod" {
  ami                    = data.aws_ami.amzn2.id
  instance_type          = "t3.micro"
  subnet_id              = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids = [aws_security_group.prod_web.id]
  key_name               = aws_key_pair.prod_key.key_name

  user_data = <<-USERDATA
    #!/bin/bash
    set -e
    yum update -y
    amazon-linux-extras install nginx1 -y || yum install -y nginx
    yum install -y unzip awscli
    systemctl enable nginx --now
    echo "<h1>Production - Waiting for Release</h1>" > /usr/share/nginx/html/index.html
  USERDATA

  tags = {
    Name = "cosmin-prod-instance"
    Env  = "prod"
  }
}

output "prod_public_ip" { value = aws_instance.prod.public_ip }