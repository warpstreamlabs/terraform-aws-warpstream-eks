# Creating the bucket, access controls and lifecycle
resource "aws_s3_bucket" "compaction_bucket" {
  bucket_prefix = substr("${local.name}-compaction-", 0, 37)
}

resource "aws_s3_bucket_public_access_block" "compaction_bucket" {
  bucket = aws_s3_bucket.compaction_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "compaction_bucket" {
  bucket = aws_s3_bucket.compaction_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "compaction_bucket" {
  depends_on = [aws_s3_bucket_ownership_controls.compaction_bucket]

  bucket = aws_s3_bucket.compaction_bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_lifecycle_configuration" "compaction_bucket" {
  bucket = aws_s3_bucket.compaction_bucket.id

  # Automatically cancel all multi-part uploads after 7d so we don't accumulate an infinite
  # number of partial uploads.
  rule {
    id     = "7d multi-part"
    status = "Enabled"
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # No other lifecycle policy. The WarpStream Agent will automatically clean up and
  # deleted expired files.
}
