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

# --- VARIABLES ---
variable "public_key" {
  description = "Public SSH key for EC2"
  type        = string
  sensitive   = true
}

# --- DATA SOURCES ---
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

# --- SECURITY GROUP ---
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

# --- KEY PAIR ---
resource "aws_key_pair" "dev_key" {
  key_name   = "cosmin-dev-key"
  public_key = var.public_key 
}

# --- ROBUST USER DATA ---
locals {
  user_data = <<-EOF
    #!/bin/bash
    # 1. Logging: Save logs to /var/log/user-data.log for debugging
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
    
    echo "Starting User Data..."

    # 2. Wait for Yum Lock (Amazon Linux updates on boot, we must wait)
    while sudo fuser /var/run/yum.pid >/dev/null 2>&1; do
       echo "Waiting for other yum processes..."
       sleep 5
    done
    
    # 3. Install
    yum update -y
    amazon-linux-extras install nginx1 -y
    yum install -y unzip
    
    # 4. Security Config (The Safe Way)
    # Nginx automatically includes /etc/nginx/conf.d/*.conf by default.
    # We do NOT touch the main nginx.conf file.
    cat <<EOT > /etc/nginx/conf.d/security_headers.conf
    server_tokens off;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    EOT

    # 5. Start Service
    systemctl enable nginx --now
    
    # 6. Permissions
    mkdir -p /usr/share/nginx/html
    chown -R ec2-user:ec2-user /usr/share/nginx/html
    
    # 7. Placeholder
    echo "<h1>Dev Environment Ready</h1>" > /usr/share/nginx/html/index.html
    echo "dev_init" > /usr/share/nginx/html/version.txt

    echo "User Data Finished Successfully."
  EOF
}

# --- EC2 INSTANCE ---
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