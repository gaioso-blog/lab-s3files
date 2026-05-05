variable "project" {
  description = "Project name"
  type        = string
}

variable "bucket_arn" {
  description = "ARN of the S3 bucket to back the file system"
  type        = string
}

variable "bucket_id" {
  description = "ID (name) of the S3 bucket - used to manage versioning alongside the file system"
  type        = string
}

variable "region" {
  description = "AWS region - used in destroy-time provisioner for AWS CLI calls"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for mount target security group"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block – restricts NFS ingress to VPC only"
  type        = string
}

variable "subnet_ids" {
  description = "All subnet IDs in the VPC (used for security group VPC association)"
  type        = list(string)
}

variable "mount_target_subnet_ids" {
  description = "Subnet IDs to create S3 Files mount targets in. Only include subnets in AZs that support S3 Files (check AWS docs for supported AZs in your region)."
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
