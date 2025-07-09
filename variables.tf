variable "resource_prefix" {
  description = "The prefix to apply to AWS resource names"
}

variable "control_plane_region" {
  description = "The region of the warpstream control plane"
}

variable "kubernetes_namespace" {
  description = "The kubernetes namespace to deploy into"
}

variable "warpstream_virtual_cluster_id" {
  description = "The warpstream virtual cluster ID"
  type        = string
}

variable "warpstream_agent_key" {
  description = "The warpstream cluster agent key"
  type        = string
  sensitive   = true
}

variable "bucket_names" {
  description = "A list of S3 bucket names that the WarpStream agents will use"
  type        = list(string)

  validation {
    condition     = length(var.bucket_names) != 0
    error_message = "Must set at least one bucket name in 'bucket_names'"
  }

}

variable "compaction_bucket_name" {
  description = "The name of the compaction bucket for low latency clusters"
  type        = string
  default     = ""
}

variable "zone_count" {
  description = "The number of zones available in the EKS cluster"
  type        = number
}

variable "eks_oidc_provider_arn" {
  description = "The oidc provider ARN for the EKS cluster"
  type        = string
}

variable "eks_oidc_issuer_url" {
  description = "The oidc issuer URL for the EKS cluster"
  type        = string
}

variable "autoscaling_min_replicas" {
  description = "The minimum number of replicas"
  type        = number
  default     = 3
}

variable "autoscaling_max_replicas" {
  description = "The maximum number of replicas"
  type        = number
  default     = 30
}

variable "additional_helm_sets" {
  description = "Additional set blocks to apply to the helm deploy"
  type = list(object({
    name  = string
    value = any
    type  = optional(string, "string")
  }))
  default = []
}

variable "additional_helm_values" {
  description = "Additional value yamls to apply to the helm deploy"
  type        = list(string)
  default     = []
}

variable "helm_chart_version" {
  description = "The version of the helm chart to deply"
  type        = string
  default     = null
}
