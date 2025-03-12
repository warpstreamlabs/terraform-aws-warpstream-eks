data "aws_iam_policy_document" "eks_service_account" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(var.eks_oidc_issuer_url, "https://", "")}:sub"

      values = ["system:serviceaccount:${var.kubernetes_namespace}:${trimsuffix(substr("${var.resource_prefix}-warpstream-agent", 0, 63), "-")}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.eks_oidc_issuer_url, "https://", "")}:aud"

      values = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_service_account" {
  name               = "${var.resource_prefix}-warpstream-agent"
  assume_role_policy = data.aws_iam_policy_document.eks_service_account.json
}

data "aws_iam_policy_document" "eks_service_account_s3_bucket" {
  count = length(var.bucket_names) == 1 ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = concat([
      for bucketName in var.bucket_names :
      "arn:aws:s3:::${bucketName}"
      ], [
      for bucketName in var.bucket_names :
      "arn:aws:s3:::${bucketName}/*"
      ]
    )
  }
}

resource "aws_iam_role_policy" "eks_service_account_s3_bucket" {
  count = length(var.bucket_names) == 1 ? 1 : 0

  name = "${var.resource_prefix}-warpstream-agent-s3"
  role = aws_iam_role.eks_service_account.id

  policy = data.aws_iam_policy_document.eks_service_account_s3_bucket[0].json
}

data "aws_iam_policy_document" "eks_service_account_s3_compaction_bucket" {
  count = length(var.compaction_bucket_name) > 0 ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = [
      "arn:aws:s3:::${var.compaction_bucket_name}",
      "arn:aws:s3:::${var.compaction_bucket_name}/*"
    ]
  }
}

resource "aws_iam_role_policy" "eks_service_account_s3_compaction_bucket" {
  count = length(var.compaction_bucket_name) > 0 ? 1 : 0

  name = "${var.resource_prefix}-warpstream-agent-s3-compaction"
  role = aws_iam_role.eks_service_account.id

  policy = data.aws_iam_policy_document.eks_service_account_s3_compaction_bucket[0].json
}

data "aws_iam_policy_document" "eks_service_account_s3express_bucket" {
  count = length(var.bucket_names) > 1 ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3express:CreateSession"
    ]

    resources = concat([
      for bucketName in var.bucket_names :
      "arn:aws:s3express:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:bucket/${bucketName}"
      ], [
      for bucketName in var.bucket_names :
      "arn:aws:s3express:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:bucket/${bucketName}/*"
      ]
    )
  }
}

resource "aws_iam_role_policy" "eks_service_account_s3express_bucket" {
  count = length(var.bucket_names) > 1 ? 1 : 0

  name = "${var.resource_prefix}-warpstream-agent-s3express"
  role = aws_iam_role.eks_service_account.id

  policy = data.aws_iam_policy_document.eks_service_account_s3express_bucket[0].json
}
