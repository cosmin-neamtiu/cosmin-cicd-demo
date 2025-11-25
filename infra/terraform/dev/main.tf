terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  # REMOTE BACKEND: DEV
  backend "s3" {
    bucket         = "cosmin-cicd-artifacts-303952966154"
    key            = "terraform/dev/state.tfstate"
    region         = "eu-central-1"
    encrypt        = true
  }
}

provider "aws" {
  region = "eu-central-1"
}

variable "public_key" {
  description = "Public SSH key for EC2"
  type        = string
  sensitive   = true
}

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

# Dev Security Group (SSH + HTTP)
resource "aws_security_group" "dev_web" {
  name        = "cosmin-dev-web-sg"
  description = "Allow HTTP and SSH for DEV"
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

resource "aws_key_pair" "dev_key" {
  key_name   = "cosmin-dev-key"
  public_key = var.public_key
}

# Robust User Data for Dev
locals {
  user_data = <<-EOF
    #!/bin/bash
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
    
    # 1. Wait for yum lock
    while sudo fuser /var/run/yum.pid >/dev/null 2>&1; do
       echo "Waiting for yum..."
       sleep 5
    done
    
    # 2. Install Nginx
    yum update -y
    amazon-linux-extras install nginx1 -y
    yum install -y unzip
    
    # 3. Security Config (The Safer Way)
    # We just create the file. Nginx loads conf.d/*.conf by default!
    # We do NOT edit nginx.conf anymore.
    cat <<EOT > /etc/nginx/conf.d/security_headers.conf
    server_tokens off;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    EOT

    # 4. Start
    systemctl enable nginx --now
    
    # 5. Web Root Permissions
    mkdir -p /usr/share/nginx/html
    chown -R ec2-user:ec2-user /usr/share/nginx/html
    
    # 6. Default Page
    echo "<h1>Dev Environment Ready</h1>" > /usr/share/nginx/html/index.html
    echo "dev_init" > /usr/share/nginx/html/version.txt
  EOF
}

resource "aws_instance" "dev" {
  ami                    = data.aws_ami.amzn2.id
  instance_type          = "t3.micro"
  subnet_id              = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids = [aws_security_group.dev_web.id]
  key_name               = aws_key_pair.dev_key.key_name
  user_data              = local.user_data

  tags = {
    Name = "cosmin-dev-instance"
    Env  = "dev"
  }
}

output "dev_public_ip" {
  value = aws_instance.dev.public_ip
}