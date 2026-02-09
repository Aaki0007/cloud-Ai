##########################
# EC2 Module - Main
##########################

# Default VPC and subnets
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Auto-select Amazon Linux 2023 AMI if none specified
data "aws_ami" "amazon_linux_2023" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023[0].id
}

# Security Group
resource "aws_security_group" "ollama" {
  name        = var.security_group_name
  description = "Security group for Ollama EC2 instance"
  vpc_id      = data.aws_vpc.default.id

  # SSH access (restricted)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  # Ollama API port (open — Lambda IPs are unpredictable)
  ingress {
    description = "Ollama API"
    from_port   = 11434
    to_port     = 11434
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound (package installs, S3 sync, model downloads)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name    = var.security_group_name
    Purpose = "Ollama EC2 security group"
  })
}

# Elastic IP for stable address across stop/start
resource "aws_eip" "ollama" {
  domain = "vpc"

  tags = merge(var.common_tags, {
    Name    = "${var.instance_name}-eip"
    Purpose = "Static IP for Ollama server"
  })
}

resource "aws_eip_association" "ollama" {
  instance_id   = aws_instance.ollama.id
  allocation_id = aws_eip.ollama.id
}

# EC2 Instance
resource "aws_instance" "ollama" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.ollama.id]
  associate_public_ip_address = true
  iam_instance_profile        = var.instance_profile_name != "" ? var.instance_profile_name : null

  key_name = var.key_pair_name != "" ? var.key_pair_name : null

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    ollama_model = var.ollama_model
    s3_bucket    = var.models_s3_bucket
    s3_prefix    = var.models_s3_prefix
    api_key      = var.api_key
  }))

  tags = merge(var.common_tags, {
    Name    = var.instance_name
    Purpose = var.purpose
  })

  lifecycle {
    ignore_changes = [user_data]
  }
}
