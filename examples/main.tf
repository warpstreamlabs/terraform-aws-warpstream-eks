locals {
  name = "ex-warpstream-eks"

  region = "us-east-1"
}

# variable "warpstream_virtual_cluster_id" {
#   description = "The warpstream virtual cluster id"
#   type        = string
# }

# variable "warpstream_agent_key" {
#   description = "The agent key for the warpstream cluster"
#   type        = string
#   sensitive   = true
# }

provider "aws" {
  region = local.region
}

# Creating a VPC for this example, you can bring your own VPC
# if you already have one and don't need to use the one created here.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.18.1"

  name = local.name

  cidr = "10.0.0.0/16"

  azs             = ["${local.region}a", "${local.region}b", "${local.region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  # Default security group in the VPC to allow all egressing.
  default_security_group_egress = [
    {
      description = "Allow all egress"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
}

# It is highly recommended to create a S3 Gateway endpoint in your VPC.
# This is to prevent S3 network traffic from egressing over your NAT Gateway and increasing costs.
module "endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "5.18.1"

  vpc_id = module.vpc.vpc_id

  create_security_group      = true
  security_group_name_prefix = "${local.name}-vpc-endpoints-"
  security_group_description = "VPC endpoint security group"

  # Security group for the endpoints.
  # We are allowing everything in the VPC to connect to the S3 endpoint.
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from VPC"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags            = { Name = local.name }
    },
    # Used for S3 Express for lower latency configurations
    # Ref: https://docs.warpstream.com/warpstream/byoc/advanced-agent-deployment-options/low-latency-clusters
    s3express = {
      service         = "s3express"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags            = { Name = local.name }
    }
  }
}

# Store the WarpStream Agent Key in AWS Secret Manager
# resource "aws_secretsmanager_secret" "warpstream_agent_key" {
#   name_prefix = "${local.name}-agent-key"
# }

# resource "aws_secretsmanager_secret_version" "warpstream_agent_key" {
#   secret_id     = aws_secretsmanager_secret.warpstream_agent_key.id
#   secret_string = var.warpstream_agent_key
# }

# Creating a EKS cluster for this example, you can bring your own cluster
# if you already have one and don't need to use the one created here.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.34.0"

  cluster_name                   = local.name
  cluster_version                = "1.31"
  cluster_endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true

  cluster_compute_config = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", local.name]
      command     = "aws"
    }
  }

}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ecs_task" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"

      values = ["system:serviceaccount:default:${trimsuffix(substr("ex-warpstream-eks-warpstream-agent", 0, 63), "-")}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"

      values = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task" {
  name               = "ex-warpstream-eks-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task.json
}

data "aws_iam_policy_document" "ec2_ecs_task_s3_bucket" {
  statement {
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = concat([
      for bucketName in [aws_s3_bucket.bucket.bucket] :
      "arn:aws:s3:::${bucketName}"
      ], [
      for bucketName in [aws_s3_bucket.bucket.bucket] :
      "arn:aws:s3:::${bucketName}/*"
      ]
    )
  }
}

resource "aws_iam_role_policy" "ec2_ecs_task_s3_bucket" {
  name = "ex-warpstream-eks-s3"
  role = aws_iam_role.ecs_task.id

  policy = data.aws_iam_policy_document.ec2_ecs_task_s3_bucket.json
}

resource "helm_release" "warpstream-agent" {
  name       = "ex-warpstream-eks"
  repository = "https://warpstreamlabs.github.io/charts"
  chart      = "warpstream-agent"

  namespace = "default"

  set {
    name  = "config.bucketURL"
    value = "s3://${aws_s3_bucket.bucket.bucket}?region=${data.aws_region.current.name}"
  }
  set {
    name  = "config.agentKey"
    value = "aks_5c13beb1fe7b49a6aa52c7f1ff17858ce604f516a3a5a392cf68ce9bd16d9744"
  }
  set {
    name  = "config.region"
    value = "us-east-1"
  }

  set {
    name  = "config.virtualClusterID"
    value = "vci_ecfbfdfc_69b7_43fb_8906_5ead15fb967a"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.ecs_task.arn
  }

  values = [<<EOT
topologySpreadConstraints:
  # Don't put pods in the same zone, with min zones matching number of subnets
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    minDomains: ${length(module.vpc.private_subnets)}
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: warpstream-agent
        app.kubernetes.io/instance: ${trimsuffix(substr("ex-warpstream-eks", 0, 63), "-")}
  # Don't put pods on the same node
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: warpstream-agent
        app.kubernetes.io/instance: ${trimsuffix(substr("ex-warpstream-eks", 0, 63), "-")}
EOT
  ]
}
