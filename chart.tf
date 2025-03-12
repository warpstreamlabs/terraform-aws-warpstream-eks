locals {
  buckets_to_urls = [for bucket_name in var.bucket_names : "s3://${bucket_name}?region=${data.aws_region.current.name}"]
  bucket_url      = length(var.bucket_names) == 1 ? local.buckets_to_urls[0] : "warpstream_multi://${join("<>", local.buckets_to_urls)}"
}

resource "helm_release" "warpstream-agent" {
  name       = var.resource_prefix
  repository = "https://warpstreamlabs.github.io/charts"
  chart      = "warpstream-agent"
  version    = var.helm_chart_version

  namespace = var.kubernetes_namespace

  dynamic "set" {
    for_each = [local.bucket_url]
    content {
      name  = length(var.bucket_names) == 1 ? "config.bucketURL" : "config.ingestionBucketURL"
      value = set.value
    }
  }

  dynamic "set" {
    for_each = length(var.bucket_names) > 1 ? ["s3://${var.compaction_bucket_name}?region=${data.aws_region.current.name}"] : []
    content {
      name  = "config.compactionBucketURL"
      value = set.value
    }
  }

  dynamic "set" {
    for_each = var.additional_helm_sets
    content {
      name  = set.value.name
      value = set.value.value
      type  = set.value.type
    }
  }

  set_sensitive {
    name  = "config.agentKey"
    value = var.warpstream_agent_key
  }

  set {
    name  = "config.region"
    value = var.control_plane_region
  }

  set {
    name  = "config.virtualClusterID"
    value = var.warpstream_virtual_cluster_id
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.eks_service_account.arn
  }

  set {
    name  = "autoscaling.enabled"
    value = true
    type  = "auto"
  }

  set {
    name  = "autoscaling.minReplicas"
    value = var.autoscaling_min_replicas
  }

  set {
    name  = "autoscaling.maxReplicas"
    value = var.autoscaling_max_replicas
  }

  values = concat(
    [<<EOT
topologySpreadConstraints:
  # Try to spread pods across multiple zones
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    minDomains: ${var.zone_count}
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: warpstream-agent
        app.kubernetes.io/instance: ${trimsuffix(substr(var.resource_prefix, 0, 63), "-")}
EOT
    ],
    [<<EOT
affinity:
  # Make sure pods are not scheduled on the same node to prevent bin packing
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          app.kubernetes.io/name: warpstream-agent
          app.kubernetes.io/instance: ${trimsuffix(substr(var.resource_prefix, 0, 63), "-")}
      topologyKey: kubernetes.io/hostname
EOT
  ], var.additional_helm_values)
}
