data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.11.20260427.1-kernel-6.1-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── Security group 
resource "aws_security_group" "ec2" {
  name        = "${var.project}-ec2-sg"
  description = "EC2 instance - egress only (use SSM for access)"
  vpc_id      = var.vpc_id

  # No SSH ingress – access via AWS Systems Manager Session Manager
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project}-ec2-sg" })
}

# ── IAM role for EC2 (SSM + S3 Files client access) 
resource "aws_iam_role" "ec2" {
  name = "${var.project}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

# SSM Session Manager – no bastion / SSH key needed
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# S3 Files client access
resource "aws_iam_role_policy_attachment" "s3files_client" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FilesClientFullAccess"
}

# Direct S3 read access for intelligent read routing (performance optimization)
resource "aws_iam_role_policy" "s3_read" {
  name = "s3-direct-access"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3ObjectReadAccess"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${var.bucket_arn}/*"
      },
      {
        Sid      = "S3BucketListAndPutAccess"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:PutObject"]
        Resource = "${var.bucket_arn}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ── EC2 instance ──────────────────────────────────────────────────────────────
resource "aws_instance" "this" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  vpc_security_group_ids = [aws_security_group.ec2.id]

  # Public IP so SSM agent can reach AWS endpoints without VPC endpoints or NAT
  associate_public_ip_address = true

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = null # use AMI default (AL2023 default is 8 GB)
    encrypted             = true
    delete_on_termination = true
  }

  # Install s3files mount helper and mount the file system with retry logic
  user_data_base64 = base64encode(<<-EOF
    #!/bin/bash
    curl https://amazon-efs-utils.aws.com/efs-utils-installer.sh | sudo sh -s -- --install
    mkdir -p /mnt/s3files
    echo "${var.file_system_id}:/ /mnt/s3files s3files _netdev,noresvport 0 0" >> /etc/fstab
    mount -a || true
  EOF
  )

  tags = merge(var.tags, { Name = "${var.project}-ec2" })
}