terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "eu-central-1"
}

# -----------------------------------------------------------------------------
# Networking & Security
# -----------------------------------------------------------------------------
data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "dev_web" {
  name        = "cosmin-dev-web-sg"
  description = "Allow HTTP and SSH for DEV"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # In prod, restrict this to your IP or VPN
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

# -----------------------------------------------------------------------------
# Compute
# -----------------------------------------------------------------------------
data "aws_ami" "amzn2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_key_pair" "dev_key" {
  key_name   = "cosmin-dev-key"
  # Ensure this file exists locally before running apply
  public_key = file(pathexpand("~/.ssh/cosmin-ec2.pub")) 
}

resource "aws_instance" "dev" {
  ami                    = data.aws_ami.amzn2.id
  instance_type          = "t3.micro"
  subnet_id              = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids = [aws_security_group.dev_web.id]
  key_name               = aws_key_pair.dev_key.key_name

  # User data to install Nginx and AWS CLI (needed for S3 pull later)
  user_data = <<-USERDATA
    #!/bin/bash
    set -e
    yum update -y
    amazon-linux-extras install nginx1 -y || yum install -y nginx
    yum install -y unzip awscli
    systemctl enable nginx --now
    echo "<h1>Dev Environment - Waiting for Deploy</h1>" > /usr/share/nginx/html/index.html
  USERDATA

  tags = {
    Name = "cosmin-dev-instance"
    Env  = "dev"
  }
}

output "dev_public_ip" { value = aws_instance.dev.public_ip }