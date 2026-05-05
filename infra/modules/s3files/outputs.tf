output "file_system_id" {
  description = "S3 Files file system ID"
  value       = aws_s3files_file_system.this.id
}

output "file_system_arn" {
  description = "S3 Files file system ARN"
  value       = aws_s3files_file_system.this.arn
}

output "mount_target_ids" {
  description = "Map of subnet ID → mount target ID"
  value       = { for k, v in aws_s3files_mount_target.this : k => v.id }
}

output "access_point_id" {
  description = "S3 Files access point ID"
  value       = aws_s3files_access_point.this.id
}

output "mount_target_sg_id" {
  description = "Security group ID attached to mount targets"
  value       = aws_security_group.mount_target.id
}
