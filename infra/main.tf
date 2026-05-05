terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket = "state-file-terraform-gaioso"
    key    = "s3files-lab/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project   = var.project
    ManagedBy = "terraform"
  }
}

# ── S3 bucket
module "s3" {
  source = "./modules/s3"

  project = var.project
  tags    = local.common_tags
}

# ── S3 Files (file system + mount targets) 
module "s3files" {
  source = "./modules/s3files"

  project                 = var.project
  bucket_arn              = module.s3.bucket_arn
  bucket_id               = module.s3.bucket_id
  region                  = var.aws_region
  vpc_id                  = var.vpc_id
  vpc_cidr                = var.vpc_cidr
  subnet_ids              = var.subnet_ids
  mount_target_subnet_ids = var.mount_target_subnet_ids
  tags                    = local.common_tags
}

# ── EC2 instance
module "ec2" {
  source = "./modules/ec2"

  project        = var.project
  vpc_id         = var.vpc_id
  subnet_id      = var.subnet_ids[0]
  instance_type  = var.instance_type
  file_system_id = module.s3files.file_system_id
  bucket_arn     = module.s3.bucket_arn
  tags           = local.common_tags
}

# Allow EC2 instance to reach the S3 Files mount targets
resource "aws_security_group_rule" "ec2_to_mount_target" {
  type                     = "ingress"
  description              = "NFS from EC2 instance"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = module.ec2.security_group_id
  security_group_id        = module.s3files.mount_target_sg_id
}