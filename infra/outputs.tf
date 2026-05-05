output "bucket_id" {
  description = "S3 bucket name"
  value       = module.s3.bucket_id
}

output "file_system_id" {
  description = "S3 Files file system ID"
  value       = module.s3files.file_system_id
}

output "mount_target_ids" {
  description = "Mount target IDs per subnet"
  value       = module.s3files.mount_target_ids
}

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = module.ec2.instance_id
}

output "ec2_private_ip" {
  description = "EC2 private IP"
  value       = module.ec2.instance_private_ip
}

output "ssm_connect_command" {
  description = "Command to open a shell on the EC2 instance via SSM"
  value       = "aws ssm start-session --target ${module.ec2.instance_id} --region ${var.aws_region}"
}

output "mount_command" {
  description = "Manual mount command (already done via fstab on boot)"
  value       = "sudo mount -t s3files ${module.s3files.file_system_id}:/ /mnt/s3files"
}
