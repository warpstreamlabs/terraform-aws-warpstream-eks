# Zonal WarpStream EKS

Configuration in this directory deploys a WarpStream cluster within EKS.

This zonal deployment deploys a single WarpStream deployment in a single zone.

This setup allows either a reduced availability in a zone outage or the ability to have independent WarpStream deployments per zone allowing more control over upgrades and autoscaling.

This example deploys three instances of the module one in each zone.
