module "labels" {
  source     = "cloudposse/label/null"
  version    = "0.25.0-rc.1"
  namespace  = var.namespace
  stage      = var.stage
  name       = var.name
  attributes = [""]
  delimiter  = "-"

  tags = {
    "Createdby" = var.createdby
  }
}
#Module      : WAF
#Description : Provides a WAFv2 IP Set Resource.
resource "aws_wafv2_ip_set" "main" {
  count = var.ip_addresses != null ? 1 : 0

  name               = var.name
  scope              = var.waf_scope
  ip_address_version = "IPV4"
  addresses          = var.ip_addresses
  tags               = module.labels.tags
}
