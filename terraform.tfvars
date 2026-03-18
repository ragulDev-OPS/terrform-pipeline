##### Region #####
region = "us-east-1"

##### lables #####
environment = "qa-uplift"
label_order = ["name", "environment"]
namespace   = "uplift"
stage       = "qa"
createdby   = "Bsetec-DevOps"

################ route53 qa ############
hosted_name = "qa.liveuplift.com"

############## ACM #############
validation_method                 = "DNS"
ttl                               = "300"
process_domain_validation_options = false
wait_for_certificate_issued       = false

##### networking #####
subnet = "subnet-0947a2dbb04577a6a"
nat_gateway_enabled             = true
single_nat_gateway              = true
cidr_block                      = "10.70.0.0/16"
availability_zones              = ["us-east-1a", "us-east-1b", "us-east-1c"]
assign_ipv6_address_on_creation = false

##### key_pair #####
enable_key_pair = true

#### kms_key #####
kms_enabled             = true
deletion_window_in_days = 7
enable_key_rotation     = true
alias                   = "alias/uplift_qa"

##### Ec2 antmedia#####
ami_owner                   = "332923349225" #"679593333241"
ec2_ami                     = "ami-0e4df00314c38ac8e"
ec2_instance_type           = "c5.xlarge"
assign_eip_address          = true
associate_public_ip_address = true
# ipv6_address_count           = 1
# ipv6_addresses               =[]
##### iam_role #####
policy_enabled = true

##### eks #######
eks_enabled               = true
kubernetes_version        = "1.32"
kubernetes_node_version   = "1.32"
endpoint_private_access   = true
endpoint_public_access    = false
enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
oidc_provider_enabled     = true
# Networking
allowed_cidr_blocks          = ["10.0.0.0/16"]
cluster_log_retention_period = "30"

#### eks block device ####
block_device_mappings = [{
  device_name           = "/dev/xvda"
  volume_size           = 50
  volume_type           = "gp3"
  iops                  = 3000
  throughput            = 150
  encrypted             = true
  delete_on_termination = true
}]

#### eks node group ####
min_size                     = 2
max_size                     = 4
desired_size                 = 2
instance_types               = ["m5.xlarge", "m5a.xlarge", "m5ad.xlarge", "m5d.xlarge", "m6a.xlarge", "m7a.xlarge", "t2.xlarge", "t3.xlarge", "t3a.xlarge"]
autoscaling_policies_enabled = true
apply_config_map_aws_auth    = false

#### critical eks node group ####
critical_min_size                     = 1
critical_max_size                     = 2
critical_desired_size                 = 1
critical_instance_types               = ["c5.large", "c5a.large", "c5ad.large", "c5d.large", "t2.medium", "t3.medium", "t3a.medium"]
critical_autoscaling_policies_enabled = true

#### redis ####
redis_engine               = "redis"
redis_engine_version       = "7.1"
redis_parameter_group_name = "redis7"
redis_node_type            = "cache.t2.medium"
redis_availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
snapshot_arns              = ["arn:aws:s3:::upliftqa-elasticcachesnap/uplift-general.rdb"]
snapshot_arns_trending     = ["arn:aws:s3:::upliftqa-elasticcachesnap/uplift-trending.rdb"]
snapshot_arns_trending_new     = ["arn:aws:s3:::upliftqa-elasticcachesnap/uplift-trending-new-0001.rdb"]
auth_token                 = "Ctd6QcKR4d6mVOtLq6Vikurka"
auth_token_trending        = "sambaCtd6QcKR4d6mVOtLq6Vikurka"
parameter_group_name_redis      = "uplift-qa-redis"
parameter_group_name_redis_trending      = "uplift-qa-trending-redis-new"
parameter_group_description = "Elasticache parameter group for uplift-qa-redis"
create_security_group = true
##################### S3 bucket ###########
acl                              = "private"
public_read_write_acl            = "public-read-write"
public_read_acl                  = "public-read"
public_block_public_acls         = false
public_block_public_policy       = false
public_ignore_public_acls        = false
public_restrict_public_buckets   = false
force_destroy                    = false
qa_category                      = "uplift-qa-category"
qa_images                        = "uplift-qa-images"
qa_videos                        = "uplift-qa-videos"
qa_admin                         = "uplift-qa-admin"
qa_assets                        = "uplift-qa-assets"
prod_email_templates_bucket_name = "cotlr-prod-email-templates"
privileged_principal_actions = [
  "s3:PutObject",
  "s3:PutObjectAcl",
  "s3:GetObject",
  "s3:DeleteObject",
  "s3:ListBucket",
  "s3:ListBucketMultipartUploads",
  "s3:GetBucketLocation",
  "s3:AbortMultipartUpload"
]
versioning_enabled            = false
user_enabled                  = false
transfer_acceleration_enabled = true

################# Transit gateway #######################
amazon_side_asn                       = 64512
enable_auto_accept_shared_attachments = true
create_tgw                            = false
share_tgw                             = true
transit_gateway_id                    = "tgw-0ce5b25297f3bbe8c"
dns_support                           = true
ipv6_support                          = false
route_table_association               = true
route_table_propagation               = true
destination_cidr_block                = ["10.0.0.0/16"]
resource_share_arn                    = "arn:aws:ram:us-east-1:309454646561:resource-share/79094fcd-0a5e-432f-9f62-ff89a0bb376a"
ram_allow_external_principals         = true
ram_principals                        = ["309454646561"]
################# waf #######################
# ip_addresses         = ["54.156.214.99/32"]
allow_default_action = "allow"
waf_enabled          = true
waf_scope            = "REGIONAL"
resource_arn_list    = ["arn:aws:elasticloadbalancing:us-east-1:870012702952:loadbalancer/app/cotlr-qa-stage-alb/350f19f4488078e4"]

################# sqs #######################
fifo_queue                  = true
content_based_deduplication = true
sqs_managed_sse_enabled     = true
delay_seconds               = 0
max_message_size            = 262144
message_retention_seconds   = 345600
receive_wait_time_seconds   = 19
visibility_timeout_seconds  = 30

####### aurora ##########
aurora_enable                       = true
username                            = "root"
db_name                             = "upliftqa_db"
engine                              = "aurora-mysql"
engine_version                      = "5.7.mysql_aurora.2.10.2"
replica_count                       = 1
instance_type                       = "db.t3.medium"
deletion_protection                 = true
apply_immediately                   = true
publicly_accessible                 = false
enabled_cloudwatch_logs_exports     = ["audit", "error", "general", "slowquery"]
iam_database_authentication_enabled = false
monitoring_interval                 = "0"
admin_password                      = "Ctd6QcKR4d6mVOtLq6Vikurka"
storage_encrypted                   = true
##### Efs #######
token                     = "upliftqa"
efs_allow_cidr            = ["10.70.0.0/16"]
efs_backup_policy_enabled = true
#### cognito ####
identity_pool_name               = "uplift-qa-identity-pool"
allow_unauthenticated_identities = true
#### SNS ####
#### SNs configurations ####
use_name_prefix             = false
create_topic_policy         = true
enable_default_topic_policy = true
topic_policy_statements = {
  pub = {
    actions = ["sns:Publish"]
    principals = [{
      type        = "AWS"
      identifiers = ["*"]
    }]
  },

  sub = {
    actions = [
      "sns:Subscribe",
      "sns:Receive",
    ]

    principals = [{
      type        = "AWS"
      identifiers = ["*"]
    }]

  }
}
#### SNS topics ####
new_mint_notification = "uplift-qa-new-mint-notification"
new_mint_notification_subscriptions = {
  http = {
    protocol = "https"
    endpoint = "https://mint-notify.qa.liveuplift.com/v1/sns-receiver"
  }
}
solr_import = "uplift-qa-solr-import"
solr_import_subscriptions = {
  http = {
    protocol = "https"
    endpoint = "https://solr-import.qa.liveuplift.com/v1/solr_import"
  }
}
tag_showrooms = "uplift-qa-tag-showrooms"
tag_showrooms_subscriptions = {
  SQS = {
    protocol = "sqs"
    endpoint = "arn:aws:sqs:us-east-1:332923349225:uplift-qa-recent-tagged-showrooms"
  }
}

