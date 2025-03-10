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
# This is prevent S3 network traffic from egressing over your NAT Gateway and increasing costs.
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

# TODO: deploy auto mode eks cluster

# TODO: use module to deploy helm + buckets
