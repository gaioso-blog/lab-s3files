variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "subnet_ids" {
  description = "All subnet IDs in the VPC. First subnet is used for the EC2 instance."
  type        = list(string)
}

variable "mount_target_subnet_ids" {
  description = "Subset of subnet IDs to create S3 Files mount targets in (only AZs that support S3 Files)"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}
