data "aws_caller_identity" "current" {}

# --- Reseau : on utilise le VPC par defaut pour simplifier ---
data "aws_vpc" "default" {
  default = true
}

# --- Derniere AMI Ubuntu 24.04 (Canonical) ---
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# --- Cle SSH (genere soc-key + soc-key.pub dans ce dossier AVANT le apply) ---
resource "aws_key_pair" "soc" {
  key_name   = var.key_name
  public_key = file("${path.module}/soc-key.pub")
}

# --- Security Group : serveur Wazuh ---
resource "aws_security_group" "wazuh" {
  name        = "soc-wazuh-sg"
  description = "Acces au serveur Wazuh"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Dashboard HTTPS (depuis ton IP uniquement)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  ingress {
    description = "SSH (depuis ton IP uniquement)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Security Group : machine cible ---
resource "aws_security_group" "victim" {
  name        = "soc-victim-sg"
  description = "Machine cible"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH (depuis ton IP, pour admin)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  ingress {
    description     = "SSH depuis le serveur Wazuh (pour la simulation de brute force)"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.wazuh.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Autorise les agents (depuis le SG cible) a parler au manager Wazuh sur 1514/1515
resource "aws_security_group_rule" "agents_to_wazuh" {
  type                     = "ingress"
  from_port                = 1514
  to_port                  = 1515
  protocol                 = "tcp"
  security_group_id        = aws_security_group.wazuh.id
  source_security_group_id = aws_security_group.victim.id
  description              = "Logs et enrolement des agents Wazuh"
}

# --- EC2 : serveur Wazuh ---
resource "aws_instance" "wazuh" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.wazuh_instance_type
  key_name               = aws_key_pair.soc.key_name
  vpc_security_group_ids = [aws_security_group.wazuh.id]
  iam_instance_profile   = aws_iam_instance_profile.wazuh_logs.name

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }
  tags = { Name = "soc-wazuh-server" }
}

# --- EC2 : machine cible ---
resource "aws_instance" "victim" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.soc.key_name
  vpc_security_group_ids = [aws_security_group.victim.id]

  # Active l'auth par mot de passe (volontairement faible, pour la demo de brute force)
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y rsyslog
              systemctl enable --now rsyslog
              echo 'ubuntu:Password123' | chpasswd
              sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
              find /etc/ssh/sshd_config.d/ -type f -exec sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' {} \;
              systemctl restart ssh
              EOF
  tags = { Name = "soc-victim" }
}

# --- S3 : bucket pour les logs CloudTrail ---
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${data.aws_caller_identity.current.account_id}-soc-cloudtrail"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      }
    ]
  })
}

# --- CloudTrail : journalise toutes les actions du compte ---
resource "aws_cloudtrail" "main" {
  name                          = "soc-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true
  depends_on                    = [aws_s3_bucket_policy.cloudtrail]
}

# --- S3 : bucket "donnees cible" (scenario d'exposition publique) ---
resource "aws_s3_bucket" "victim_data" {
  bucket        = "${data.aws_caller_identity.current.account_id}-soc-victim-data"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "victim_data" {
  bucket                  = aws_s3_bucket.victim_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- IAM : role attache a l'instance Wazuh pour LIRE les logs CloudTrail ---
resource "aws_iam_role" "wazuh_logs" {
  name = "soc-wazuh-logs-reader"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "wazuh_logs" {
  name = "read-cloudtrail-bucket"
  role = aws_iam_role.wazuh_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.cloudtrail.arn, "${aws_s3_bucket.cloudtrail.arn}/*"]
    }]
  })
}

resource "aws_iam_instance_profile" "wazuh_logs" {
  name = "soc-wazuh-logs-profile"
  role = aws_iam_role.wazuh_logs.name
}
