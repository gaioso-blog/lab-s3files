data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Enable versioning before file system is created 
# S3 Files requires versioning to be enabled on the bucket.
# This runs first (file system depends on it), and the destroy provisioner
# handles cleanup: deletes the file system, empties the bucket.
resource "null_resource" "enable_versioning" {
  triggers = {
    bucket_id = var.bucket_id
    region    = var.region
  }

  provisioner "local-exec" {
    when    = create
    command = "aws s3api put-bucket-versioning --bucket ${self.triggers.bucket_id} --versioning-configuration Status=Enabled --region ${self.triggers.region}"
  }
}

# ── IAM role assumed by the S3 Files service 
resource "aws_iam_role" "this" {
  name = "${var.project}-s3files-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowS3FilesAssumeRole"
      Effect    = "Allow"
      Principal = { Service = "elasticfilesystem.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:s3files:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:file-system/*"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "bucket_access" {
  name = "s3files-bucket-access"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketPermissions"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:ListBucketVersions"
        ]
        Resource = var.bucket_arn
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "S3ObjectPermissions"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:DeleteObject*",
          "s3:GetObject*",
          "s3:List*",
          "s3:PutObject*"
        ]
        Resource = "${var.bucket_arn}/*"
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "EventBridgeManage"
        Effect = "Allow"
        Action = [
          "events:DeleteRule",
          "events:DisableRule",
          "events:EnableRule",
          "events:PutRule",
          "events:PutTargets",
          "events:RemoveTargets"
        ]
        Resource = "arn:aws:events:*:*:rule/DO-NOT-DELETE-S3-Files*"
        Condition = {
          StringEquals = {
            "events:ManagedBy" = "elasticfilesystem.amazonaws.com"
          }
        }
      },
      {
        Sid    = "EventBridgeRead"
        Effect = "Allow"
        Action = [
          "events:DescribeRule",
          "events:ListRuleNamesByTarget",
          "events:ListRules",
          "events:ListTargetsByRule"
        ]
        Resource = "arn:aws:events:*:*:rule/*"
      }
    ]
  })
}

# ── File system 
resource "aws_s3files_file_system" "this" {
  bucket   = var.bucket_arn
  role_arn = aws_iam_role.this.arn

  tags = var.tags

  depends_on = [
    aws_iam_role_policy.bucket_access,
    null_resource.enable_versioning, # versioning must be on before file system is created
  ]
}

# ── Destroy-time cleanup 
# Runs before the bucket is deleted. Deletes the file system + mount targets,
# waits for full deletion, then empties all versioned objects from the bucket.
# Stored in triggers so values are available at destroy time (var.* not allowed).
resource "null_resource" "fs_cleanup" {
  triggers = {
    bucket_id      = var.bucket_id
    region         = var.region
    file_system_id = aws_s3files_file_system.this.id
  }

  provisioner "local-exec" {
    when    = destroy
    interpreter = ["bash", "-c"]
    command = <<-EOT
      BUCKET="${self.triggers.bucket_id}"
      REGION="${self.triggers.region}"

      echo "==> Finding file systems attached to s3://$BUCKET..."
      for fs in $(aws s3files list-file-systems --region $REGION \
            --query "FileSystems[?Bucket=='arn:aws:s3:::$BUCKET'].FileSystemId" \
            --output text 2>/dev/null); do

        echo "==> Deleting mount targets for $fs..."
        for mt in $(aws s3files list-mount-targets --file-system-id $fs --region $REGION \
              --query 'MountTargets[].MountTargetId' --output text 2>/dev/null); do
          aws s3files delete-mount-target --mount-target-id $mt --region $REGION 2>/dev/null || true
          echo "    Deleted mount target $mt"
        done

        echo "==> Deleting file system $fs..."
        aws s3files delete-file-system --file-system-id $fs --region $REGION 2>/dev/null || true

        echo "==> Waiting for $fs to be fully deleted..."
        for i in $(seq 1 40); do
          STATUS=$(aws s3files get-file-system --file-system-id $fs --region $REGION \
            --query 'FileSystem.LifeCycleState' --output text 2>&1 || echo "DELETED")
          echo "    [$i] $STATUS"
          if echo "$STATUS" | grep -qiE "DELETED|does not exist|ResourceNotFoundException|NonExistent"; then
            echo "    File system $fs deleted."
            break
          fi
          sleep 15
        done
      done

      echo "==> Emptying versioned objects from $BUCKET..."
      VERSIONS=$(aws s3api list-object-versions --bucket $BUCKET --region $REGION \
        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
        --output json 2>/dev/null)
      if [ -n "$VERSIONS" ] && [ "$VERSIONS" != "null" ] && [ "$VERSIONS" != '{"Objects": null}' ]; then
        aws s3api delete-objects --bucket $BUCKET --region $REGION --delete "$VERSIONS" 2>/dev/null || true
        echo "    Versioned objects deleted."
      fi

      MARKERS=$(aws s3api list-object-versions --bucket $BUCKET --region $REGION \
        --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
        --output json 2>/dev/null)
      if [ -n "$MARKERS" ] && [ "$MARKERS" != "null" ] && [ "$MARKERS" != '{"Objects": null}' ]; then
        aws s3api delete-objects --bucket $BUCKET --region $REGION --delete "$MARKERS" 2>/dev/null || true
        echo "    Delete markers removed."
      fi

      echo "==> Done. Bucket is empty and file system is detached."
    EOT
  }
}

# ── Security group for mount targets (NFS port 2049) 
resource "aws_security_group" "mount_target" {
  name        = "${var.project}-s3files-mt-sg"
  description = "S3 Files mount target - allows NFS from within VPC"
  vpc_id      = var.vpc_id

  ingress {
    description = "NFS from VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project}-s3files-mt-sg" })
}

# ── Mount targets - one per subnet / AZ 
# Only pass subnets in AZs where S3 Files is supported.
# Not all AZs in a region support S3 Files mount targets.
resource "aws_s3files_mount_target" "this" {
  for_each = toset(var.mount_target_subnet_ids)

  file_system_id  = aws_s3files_file_system.this.id
  subnet_id       = each.value
  security_groups = [aws_security_group.mount_target.id]
}

# ── Access point 
resource "aws_s3files_access_point" "this" {
  file_system_id = aws_s3files_file_system.this.id
  tags           = var.tags
}
