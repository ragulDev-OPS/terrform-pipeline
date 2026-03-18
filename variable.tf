#### region ####
variable "region" {

}
# variable "access_key" {

# }

# variable "secret_key" {

# }

#### lables ####
variable "environment" {

}
variable "label_order" {

}

variable "namespace" {

}
variable "stage" {

}
variable "createdby" {

}

#### Route 53 ####
variable "hosted_name" {
}

##### ACM #####

variable "process_domain_validation_options" {
}

variable "ttl" {

}
variable "wait_for_certificate_issued" {

}

variable "validation_method" {

}


#### networking ####
variable "cidr_block" {

}

variable "subnet" {

}

variable "nat_gateway_enabled" {

}

variable "single_nat_gateway" {

}

variable "availability_zones" {

}

variable "assign_ipv6_address_on_creation" {

}

#### key_pair ####

variable "enable_key_pair" {

}

#### iam_role ####
variable "policy_enabled" {

}

#### kms_key #####
variable "kms_enabled" {

}

variable "deletion_window_in_days" {

}

variable "enable_key_rotation" {

}

variable "alias" {

}
##### Ec2 ####
variable "ec2_ami" {

}

variable "ec2_instance_type" {

}

variable "assign_eip_address" {

}

variable "associate_public_ip_address" {

}
variable "ami_owner" {

}

# variable "ipv6_address_count" {

# }

# variable "ipv6_addresses" {

# }
##### eks #######
variable "eks_enabled" {

}

variable "kubernetes_version" {

}

variable "kubernetes_node_version" {

}

variable "endpoint_private_access" {

}

variable "endpoint_public_access" {

}

variable "enabled_cluster_log_types" {

}

variable "oidc_provider_enabled" {

}

variable "allowed_cidr_blocks" {

}

variable "block_device_mappings" {

}

variable "apply_config_map_aws_auth" {

}

variable "instance_types" {

}

variable "desired_size" {

}

variable "max_size" {

}

variable "min_size" {

}

variable "autoscaling_policies_enabled" {

}
variable "cluster_log_retention_period" {

}

variable "critical_instance_types" {

}

variable "critical_desired_size" {

}

variable "critical_max_size" {

}

variable "critical_min_size" {

}

variable "critical_autoscaling_policies_enabled" {

}
variable "manage_aws_auth_configmap" {
  type = bool
  default = true
}
variable "access_config" {
  type = object({
    authentication_mode                         = optional(string, "API")
    bootstrap_cluster_creator_admin_permissions = optional(bool, false)
  })
  description = "Access configuration for the EKS cluster."
  default     = {}
  nullable    = false

  # validation {
  #   condition     = !contains(["CONFIG_MAP"], var.access_config.authentication_mode)
  #   error_message = "The CONFIG_MAP authentication_mode is not supported."
  # }
}
# variable "prevent_duplicate_rules" {
#   type = bool
#   default = true
# }
#### redis ####
variable "redis_engine" {

}

variable "redis_engine_version" {

}

variable "redis_parameter_group_name" {

}

variable "redis_node_type" {

}

variable "redis_availability_zones" {

}

variable "snapshot_arns" {

}

variable "auth_token" {

}

variable "snapshot_arns_trending" {

}

variable "snapshot_arns_trending_new" {

} 
variable "auth_token_trending" {

}
variable "parameter_group_name_redis" {
  type        = string
  default     = null
}
variable "parameter_group_name_redis_trending" {
  type        = string
  default     = null
}
variable "parameter_group_description" {
}
variable "security_group_create_before_destroy" {
  type = bool
  default = false
}
variable "create_parameter_group" {
  type = bool
  default = false
}

variable "create_security_group" {
  type        = bool
  default     = false
  description = "Set `true` to create and configure a new security group. If false, `associated_security_group_ids` must be provided."
}
#### s3 bucket ####
variable "user_enabled" {

}

variable "acl" {

}
variable "public_read_write_acl" {

}
variable "public_read_acl" {

}
variable "public_block_public_acls" {

}
variable "public_block_public_policy" {

}
variable "public_ignore_public_acls" {

}
variable "public_restrict_public_buckets" {

}
variable "force_destroy" {

}

variable "versioning_enabled" {

}

variable "qa_category" {

}
variable "qa_images" {

}
variable "qa_videos" {

}
variable "qa_admin" {

}
variable "qa_assets" {

}

variable "prod_email_templates_bucket_name" {

}

variable "privileged_principal_actions" {

}

variable "transfer_acceleration_enabled" {

}


#### transit-gateway ####
variable "amazon_side_asn" {

}
variable "resource_share_arn" {

}
variable "transit_gateway_id" {

}
variable "create_tgw" {

}
variable "share_tgw" {

}
variable "dns_support" {

}
variable "ipv6_support" {

}
variable "route_table_association" {

}
variable "route_table_propagation" {

}
variable "destination_cidr_block" {

}
variable "ram_principals" {

}
variable "enable_auto_accept_shared_attachments" {

}
variable "ram_allow_external_principals" {

}

###### waf ######

# variable "ip_addresses" {

# }

variable "allow_default_action" {

}

variable "waf_enabled" {

}

variable "waf_scope" {

}

variable "resource_arn_list" {

}

###### cloudwatch events ######
# variable "learning-lambda-worker-prod" {}
# variable "news-lambda-worker-prod" {}
# variable "user-lambda-worker-prod" {}
# variable "general-worker-prod" {}
# variable "exchange-lambda-worker-prod" {}
# variable "feed-video-worker-prod" {}
# variable "event-worker-prod" {}

####### aurora #########
variable "aurora_enable" {

}

variable "username" {

}

variable "engine" {

}

variable "db_name" {

}

variable "admin_password" {

}

variable "engine_version" {

}

variable "replica_count" {

}

variable "instance_type" {

}

variable "deletion_protection" {

}

variable "apply_immediately" {

}

variable "publicly_accessible" {

}

variable "enabled_cloudwatch_logs_exports" {

}

variable "iam_database_authentication_enabled" {

}

variable "monitoring_interval" {

}
variable "storage_encrypted" {

}
###### sqs ######
variable "fifo_queue" {

}
variable "content_based_deduplication" {

}
variable "sqs_managed_sse_enabled" {

}
variable "delay_seconds" {

}
variable "max_message_size" {

}
variable "message_retention_seconds" {

}
variable "receive_wait_time_seconds" {

}
variable "visibility_timeout_seconds" {

}
#### Efs ####

variable "token" {

}

variable "efs_allow_cidr" {

}

variable "efs_backup_policy_enabled" {

}
#### Cognito####
variable "identity_pool_name" {

}
variable "allow_unauthenticated_identities" {

}
#### SNS ####
variable "use_name_prefix" {

}
variable "create_topic_policy" {

}
variable "enable_default_topic_policy" {

}
variable "topic_policy_statements" {

}
variable "new_mint_notification" {

}
variable "new_mint_notification_subscriptions" {

}
variable "solr_import" {

}
variable "solr_import_subscriptions" {

}
variable "tag_showrooms" {

}
variable "tag_showrooms_subscriptions" {

}
variable "https_ssl_policy" {
  type        = string
  description = "The name of the SSL Policy for the listener"
  default     = "ELBSecurityPolicy-2015-05"
}
################# vpc #######################
variable "addons" {
  type = list(object({
    addon_name    = string
    addon_version = string
    # resolve_conflicts is deprecated, but we keep it for backwards compatibility
    # and because if not declared, Terraform will silently ignore it.
    resolve_conflicts           = optional(string, null)
    resolve_conflicts_on_create = optional(string, null)
    resolve_conflicts_on_update = optional(string, null)
    service_account_role_arn    = string
  }))
  default     = []
  description = "Manages [`aws_eks_addon`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) resources."
}
