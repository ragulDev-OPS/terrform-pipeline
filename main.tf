provider "aws" {
  region = var.region
  # access_key = var.access_key
  # secret_key = var.secret_key
  profile = "uplift-qa"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    awsutils = {
      source  = "cloudposse/awsutils"
      version = "0.20.1" # 0.18.1
    }
  }
  # required_version = ">= 1.1.7"
}

terraform {
  backend "s3" {
    bucket = "qa-uplift-terraform-aws"
    region = "us-east-1"
    # access_key = var.access_key
    # secret_key = var.secret_key
    profile = "uplift-qa"
    key     = "qa.tfstate"
  }
}

provider "awsutils" {
  region  = var.region
  profile = "uplift-qa"
}
#####################################################################
## Label
#####################################################################
module "label" {
  source     = "cloudposse/label/null"
  version    = "0.25.0"
  namespace  = var.namespace
  stage      = var.stage
  name       = ""
  attributes = [""]
  delimiter  = "-"

  tags = {
    "Createdby" = var.createdby
  }
}
####################################################################
# Route53 QA
####################################################################
module "aws_route53_hosted_zone" {
  source  = "cloudposse/route53-cluster-zone/aws"
  version = "0.16.1" # 0.16.0
  name    = "hosted-zone"

  zone_name                  = var.hosted_name
  parent_zone_record_enabled = false

  context = module.label.context
}

####################################################################
# ACM
####################################################################
module "acm" {
  source = "cloudposse/acm-request-certificate/aws"
  version = "0.18.0" # 0.16.3
  name   = "ssl-certficate"

  domain_name                       = var.hosted_name
  validation_method                 = var.validation_method
  ttl                               = var.ttl
  subject_alternative_names         = ["*.${var.hosted_name}"]
  process_domain_validation_options = var.process_domain_validation_options
  wait_for_certificate_issued       = var.wait_for_certificate_issued
  context                           = module.label.context
}
# #####################################################################
# ## VPC
# #####################################################################
module "vpc" {
  source  = "cloudposse/vpc/aws"
  version = "2.2.0" # 2.1.0
  name   = "vpc"

  ipv4_primary_cidr_block = var.cidr_block

  assign_generated_ipv6_cidr_block = true
  context                          = module.label.context
}

  data "aws_caller_identity" "current" {}

  # IAM session context converts an assumed role ARN into an IAM Role ARN.
  # Again, this is primarily to simplify the example, and in practice, you should use a static map of IAM users or roles.
  data "aws_iam_session_context" "current" {
    arn = data.aws_caller_identity.current.arn
  }

locals {
    # The usage of the specific kubernetes.io/cluster/* resource tags below are required
    # for EKS and Kubernetes to discover and manage networking resources
    # https://aws.amazon.com/premiumsupport/knowledge-center/eks-vpc-subnet-discovery/
    # https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/main/docs/deploy/subnet_discovery.md
    #tags = { "kubernetes.io/cluster/${module.label.id}" = "qa" }

    # required tags to make ALB ingress work https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html
    public_subnets_additional_tags = {
      "kubernetes.io/role/elb" : 1
    }
    private_subnets_additional_tags = {
      "kubernetes.io/role/internal-elb" : 1
    }

    extra_policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"

    # Enable the IAM user creating the cluster to administer it,
    # without using the bootstrap_cluster_creator_admin_permissions option,
    # as an example of how to use the access_entry_map feature.
    # In practice, this should be replaced with a static map of IAM users or roles
    # that should have access to the cluster, but we use the current user
    # to simplify the example.
    # access_entry_map = {
    #   (data.aws_iam_session_context.current.issuer_arn) = {
    #     access_policy_associations = {
    #       ClusterAdmin = {}
    #     }
    #   }
    # }

    # https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html#vpc-cni-latest-available-version
  vpc_cni_addon = {
    addon_name               = "vpc-cni"
    addon_version            = "v1.19.6-eksbuild.1"
    resolve_conflicts_on_create       = "OVERWRITE"
    resolve_conflicts_on_update       = "OVERWRITE"
    service_account_role_arn = null 
  }
  # // https://docs.aws.amazon.com/eks/latest/userguide/managing-kube-proxy.html
  kube_proxy_addon = {
    addon_name                  = "kube-proxy"
    addon_version               = "v1.32.5-eksbuild.2"
    resolve_conflicts_on_create       = "OVERWRITE"
    resolve_conflicts_on_update       = "OVERWRITE"
    service_account_role_arn = null 

  }
  #   // https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html
  coredns_addon = {
    addon_name                  = "coredns"
    addon_version               = "v1.11.4-eksbuild.14"
    resolve_conflicts_on_create       = "OVERWRITE"
    resolve_conflicts_on_update       = "OVERWRITE"
    service_account_role_arn = null 
  }
  addons = concat([
    local.vpc_cni_addon, local.kube_proxy_addon, local.coredns_addon
  ], var.addons)
  }
# #####################################################################
# ## Subnets
# #####################################################################
module "subnets" {
  source    = "cloudposse/dynamic-subnets/aws"
  version   = "2.4.2" # 2.4.1
  name      = "subnets"
  stage     = var.stage
  namespace = var.namespace


  vpc_id                  = sensitive(module.vpc.vpc_id)
  igw_id                  = [module.vpc.igw_id]
  ipv4_cidr_block         = [module.vpc.vpc_cidr_block]
  availability_zones      = var.availability_zones
  ipv6_cidr_block         = [module.vpc.vpc_ipv6_cidr_block]
  nat_gateway_enabled     = true
  nat_instance_enabled    = false
  private_subnets_enabled = true
  public_subnets_enabled  = true
  private_subnets_additional_tags = {
    "Type"                            = "private",
    "kubernetes.io/role/internal-elb" = "1"
  }

  public_subnets_additional_tags = {
    "Type"                   = "public",
    "kubernetes.io/role/elb" = "1"
  }

  public_assign_ipv6_address_on_creation  = false
  private_assign_ipv6_address_on_creation = false
  max_subnet_count                        = 6
  max_nats                                = 1

  tags = {
    "Createdby"  = var.createdby
    "Attributes" = ""
  }
}
# #####################################################################
# ## Security Group
# #####################################################################
## Security Group - ssh
module "ssh" {
  source  = "cloudposse/security-group/aws"
  version = "2.2.0"
  name   = "sg-ssh"

  # Allow unlimited egress
  allow_all_egress = true

  rules = [
    {
      key         = "ssh"
      type        = "ingress"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
    }
  ]
  # create_before_destroy	=false
  # preserve_security_group_id=true
  vpc_id  = sensitive(module.vpc.vpc_id)
  context = module.label.context
}
## Security Group - Lambda internal ssh
module "lambda-internal-ssh" {
  source  = "cloudposse/security-group/aws"
  version = "2.2.0"

  name = "sg-lambda"

  # Allow unlimited egress
  allow_all_egress = true

  rules = [
    {
      key         = "lambda-internal-ssh"
      type        = "ingress"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "MYSQL/Aurora"
      type        = "ingress"
      from_port   = 3306
      to_port     = 3306
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp1"
      type        = "ingress"
      from_port   = 7001
      to_port     = 7001
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp2"
      type        = "ingress"
      from_port   = 4171
      to_port     = 4171
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp3"
      type        = "ingress"
      from_port   = 8983
      to_port     = 8983
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp4"
      type        = "ingress"
      from_port   = 8984
      to_port     = 8984
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp5"
      type        = "ingress"
      from_port   = 5622
      to_port     = 5622
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp6"
      type        = "ingress"
      from_port   = 3000
      to_port     = 3000
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp7"
      type        = "ingress"
      from_port   = 6003
      to_port     = 6003
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp8"
      type        = "ingress"
      from_port   = 6005
      to_port     = 6005
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp9"
      type        = "ingress"
      from_port   = 9015
      to_port     = 9015
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp10"
      type        = "ingress"
      from_port   = 2002
      to_port     = 2002
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp11"
      type        = "ingress"
      from_port   = 5001
      to_port     = 5001
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp12"
      type        = "ingress"
      from_port   = 5004
      to_port     = 5004
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp13"
      type        = "ingress"
      from_port   = 2005
      to_port     = 2005
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp14"
      type        = "ingress"
      from_port   = 5445
      to_port     = 5445
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp15"
      type        = "ingress"
      from_port   = 9016
      to_port     = 9016
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp16"
      type        = "ingress"
      from_port   = 9017
      to_port     = 9017
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp17"
      type        = "ingress"
      from_port   = 3004
      to_port     = 3004
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
    }
  ]

  vpc_id  = sensitive(module.vpc.vpc_id)
  context = module.label.context
}

module "lambda-internal-ssh2" {
  source  = "cloudposse/security-group/aws"
  version = "2.2.0"

  name = "sg-lambda-01"

  # Allow unlimited egress
  allow_all_egress = true

  rules = [
    {
      key         = "custom-tcp18"
      type        = "ingress"
      from_port   = 5444
      to_port     = 5444
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp19"
      type        = "ingress"
      from_port   = 2004
      to_port     = 2004
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp20"
      type        = "ingress"
      from_port   = 11211
      to_port     = 11211
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp21"
      type        = "ingress"
      from_port   = 6004
      to_port     = 6004
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp22"
      type        = "ingress"
      from_port   = 5400
      to_port     = 5400
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp23"
      type        = "ingress"
      from_port   = 6379
      to_port     = 6379
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp24"
      type        = "ingress"
      from_port   = 5003
      to_port     = 5003
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp25"
      type        = "ingress"
      from_port   = 3007
      to_port     = 3007
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp26"
      type        = "ingress"
      from_port   = 6001
      to_port     = 6001
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp27"
      type        = "ingress"
      from_port   = 2006
      to_port     = 2006
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp28"
      type        = "ingress"
      from_port   = 5000
      to_port     = 5000
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp29"
      type        = "ingress"
      from_port   = 8983
      to_port     = 8983
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp30"
      type        = "ingress"
      from_port   = 7008
      to_port     = 7008
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp31"
      type        = "ingress"
      from_port   = 5002
      to_port     = 5002
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp32"
      type        = "ingress"
      from_port   = 5080
      to_port     = 5080
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp33"
      type        = "ingress"
      from_port   = 3003
      to_port     = 3003
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "custom-tcp34"
      type        = "ingress"
      from_port   = 8088
      to_port     = 8088
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
      self        = null
      }, {
      key         = "http"
      type        = "ingress"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      self        = null
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      key         = "https"
      type        = "ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      self        = null
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  vpc_id  = sensitive(module.vpc.vpc_id)
  context = module.label.context
}
## Security Group - http and https
module "http-https" {
  source  = "cloudposse/security-group/aws"
  version = "2.2.0"

  name = "sg-http-https"

  # Allow unlimited egress
  allow_all_egress = true

  rules = [
    {
      key         = "http"
      type        = "ingress"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      self        = null
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      key         = "https"
      type        = "ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      self        = null
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  vpc_id = sensitive(module.vpc.vpc_id)

  context = module.label.context
}
# ## Security Group - mongo db
# module "antmedia" {
#   source  = "cloudposse/security-group/aws"
#   version = "2.2.0"

#   name = "sg-antmedia"

#   # Allow unlimited egress
#   allow_all_egress = true

#   rules = [
#     {
#       key         = "antmedia"
#       type        = "ingress"
#       from_port   = 27017
#       to_port     = 27017
#       protocol    = "tcp"
#       cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
#       self        = null
#       }, {
#       key         = "ssh"
#       type        = "ingress"
#       from_port   = 22
#       to_port     = 22
#       protocol    = "tcp"
#       cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16"]
#       self        = null
#       }, {
#       key         = "antmedia-tcp"
#       type        = "ingress"
#       from_port   = 5080
#       to_port     = 5080
#       protocol    = "tcp"
#       cidr_blocks = ["0.0.0.0/0"]
#       self        = null
#       }, {
#       key         = "antmedia-udp"
#       type        = "ingress"
#       from_port   = 5000
#       to_port     = 65000
#       protocol    = "udp"
#       cidr_blocks = ["0.0.0.0/0"]
#       self        = null
#     }
#   ]

#   vpc_id = sensitive(module.vpc.vpc_id)

#   context = module.label.context
# }
## Security Group - redis
module "redis-sg" {
  source  = "cloudposse/security-group/aws"
  version = "2.2.0"
  name   = "sg-redis"

  # Allow unlimited egress
  allow_all_egress = true

  rules = [
    {
      key         = "elastic-cache"
      type        = "ingress"
      from_port   = 6379
      to_port     = 6379
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block]
      self        = null
    },
    {
      key         = "elastic-cache-base"
      type        = "ingress"
      from_port   = 6379
      to_port     = 6379
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/16"]
      self        = null
    }
  ]

  vpc_id  = sensitive(module.vpc.vpc_id)
  context = module.label.context
}
###########################################################################
#redis-sg-new
###########################################################################
module "redis-sg-new" {
  source  = "cloudposse/security-group/aws"
  version = "2.2.0"
  name   = "sg-redis-new"

  # Allow unlimited egress
  allow_all_egress = true

  rules = [
    {
      key         = "elastic-cache"
      type        = "ingress"
      from_port   = 6379
      to_port     = 6379
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block]
      self        = null
    },
    {
      key         = "elastic-cache-base"
      type        = "ingress"
      from_port   = 6379
      to_port     = 6379
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/16"]
      self        = null
    }
  ]
  create_before_destroy	=false
  preserve_security_group_id=true
  vpc_id  = sensitive(module.vpc.vpc_id)
  context = module.label.context
}

#####################################################################
## Keypair
#####################################################################
module "key_pair" {
  source = "../bsetec/terraform-aws-key-pair-0.20.0"

  name = "key-pair"

  generate_ssh_key    = false
  ssh_public_key_path = "./secrets"
  ssh_public_key_file = "uplift-qa.pub"
  context             = module.label.context
}
#####################################################################
## EKS
#####################################################################
module "eks_node_group" {
  source  = "../bsetec/terraform-aws-eks-node-group-main-3.3.1"
  #version = "3.3.1" #2.11.0

  name             = "node-app"
  instance_types   = var.instance_types
  subnet_ids       = module.subnets.private_subnet_ids
  ec2_ssh_key_name = [module.key_pair.key_name]
  #health_check_type     = var.health_check_type
  min_size                    = var.min_size
  max_size                    = var.max_size
  desired_size                = var.desired_size
  cluster_name                = module.eks_cluster.eks_cluster_id
  block_device_mappings       = var.block_device_mappings
  detailed_monitoring_enabled = true
  capacity_type               = "SPOT"
  # Enable the Kubernetes cluster auto-scaler to find the auto-scaling group
  cluster_autoscaler_enabled = var.autoscaling_policies_enabled
  kubernetes_version         = var.kubernetes_node_version == null || var.kubernetes_node_version == "" ? [] : [var.kubernetes_node_version]
  create_before_destroy      = true
  ami_type            = "AL2023_x86_64_STANDARD"
  ami_release_version = ["1.32.3-20250610"]
  context = module.label.context

  # Ensure the cluster is fully created before trying to add the node group
  #module_depends_on = module.eks_cluster.kubernetes_config_map_id
}

module "eks_node_group_critical" {
  source  = "../bsetec/terraform-aws-eks-node-group-main-3.3.1"
  #version = "2.11.0"

  name             = "node-critical"
  instance_types   = var.critical_instance_types
  subnet_ids       = module.subnets.private_subnet_ids
  ec2_ssh_key_name = [module.key_pair.key_name]
  #health_check_type     = var.health_check_type
  min_size                    = var.critical_min_size
  max_size                    = var.critical_max_size
  desired_size                = var.critical_desired_size
  cluster_name                = module.eks_cluster.eks_cluster_id
  block_device_mappings       = var.block_device_mappings
  detailed_monitoring_enabled = true
  capacity_type               = "SPOT"
  # Enable the Kubernetes cluster auto-scaler to find the auto-scaling group
  cluster_autoscaler_enabled = var.critical_autoscaling_policies_enabled
  kubernetes_version         = var.kubernetes_node_version == null || var.kubernetes_node_version == "" ? [] : [var.kubernetes_node_version]
  create_before_destroy      = true
  ami_type            = "AL2023_x86_64_STANDARD"
  ami_release_version = ["1.32.3-20250610"]
  context = module.label.context

  # Ensure the cluster is fully created before trying to add the node group
  #module_depends_on = module.eks_cluster.kubernetes_config_map_id
}

module "eks_cluster" {
  source             = "../bsetec/terraform-aws-eks-cluster-4.6.0"
  #version            = "2.9.0" 
  cluster_attributes = [""]

  region                    = var.region
  endpoint_private_access   = var.endpoint_private_access
  endpoint_public_access    = var.endpoint_public_access
  enabled_cluster_log_types = var.enabled_cluster_log_types
  #vpc_id                    = sensitive(module.vpc.vpc_id)
  subnet_ids                = module.subnets.public_subnet_ids
  allowed_cidr_blocks       = var.allowed_cidr_blocks

  kubernetes_version        = var.kubernetes_version
  oidc_provider_enabled     = var.oidc_provider_enabled
  #apply_config_map_aws_auth = var.apply_config_map_aws_auth
  cluster_log_retention_period = var.cluster_log_retention_period
  context                   = module.label.context
  addons                                = local.addons
  addons_depends_on                     = [module.eks_node_group]
  #access_entry_map = local.access_entry_map
  access_config = {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = false
  }
}
#####################################################################
## ECR
#####################################################################
module "upliftqa-complimint-conversation-sqs-worker" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "complimint-conversation-sqs-worker"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context

}

module "upliftqa-firehose-sqs-worker" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "firehose-sqs-worker"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-gamification-cron" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "gamification-cron"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-gamification-worker" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "gamification-worker"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-inspirationscore-worker" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "inspirationscore-worker"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-ms-activity-worker" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "ms-activity-worker"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-ms-emailservice" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "ms-emailservice"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-ms-imagemints-worker" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "ms-imagemints-worker"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-ms-mints-worker" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "ms-mints-worker"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-ms-showroom-worker" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "ms-showroom-worker"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-ms-upliftzone" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "ms-upliftzone"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-trending_worker" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "trending_worker"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-ms-user-delete-service-worker" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "ms-user-delete-service-worker"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-video-zencoder-worker" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "video-zencoder-worker"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-welcome_mint_worker" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "welcome_mint_worker"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-ms-livestream" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "ms-livestream"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-admin-frontend" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "admin-frontend"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-share-landing" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "share-landing"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-ms-notify" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "ms-notify"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-ms-complimint-user-firebase" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "ms-complimint-user-firebase"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-ms-solr-import" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "ms-solr-import"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-ms-new-mint-notification" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "ms-new-mint-notification"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

module "upliftqa-ms-activity-cron" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "ms-activity-cron"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}
module "upliftqa-profile-worker" {
  source               = "cloudposse/ecr/aws"
  version              = "0.42.1" # 0.38.0
  name                 = "profile-worker"
  scan_images_on_push  = true
  image_tag_mutability = "MUTABLE"
  max_image_count      = 50

  context = module.label.context
}

# ######################################################################
# ## SQS
# ######################################################################
locals {
  tags_sqs = {
    Createdby = var.createdby
    Namespace = var.namespace
    Stage     = var.stage

  }
}
## complimint_sqs
module "uplift-qa-complimint-sqs" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-complimint-sqs"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-complimint-sqs
  tags = {
    Name      = "uplift-qa-complimint-sqs"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-complimint-sqs = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-complimint-sqs.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}

# ## common_delete_worker
module "uplift-qa-common-delete-worker" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-common-delete-worker"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-common-delete-worker
  tags = {
    Name      = "uplift-qa-common-delete-worker"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }
}

locals {
  uplift-qa-common-delete-worker = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-common-delete-worker.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}

# ## dev_delete_showroom

module "uplift-qa-delete-showroom" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-delete-showroom"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-delete-showroom
  tags = {
    Name      = "uplift-qa-delete-showroom"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }
}
locals {
  uplift-qa-delete-showroom = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-delete-showroom.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}

# ## dev_live_stream fifo

module "uplift-qa-live-stream-fifo" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-live-stream.fifo"

  fifo_queue                  = var.fifo_queue
  content_based_deduplication = var.content_based_deduplication
  sqs_managed_sse_enabled     = var.sqs_managed_sse_enabled
  create_queue_policy         = true
  queue_policy_statements     = local.uplift-qa-live-stream-fifo

  tags = {
    Name      = "uplift-qa-live-stream.fifo"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}
locals {
  uplift-qa-live-stream-fifo = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-live-stream-fifo.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}

## email notification
module "uplift-qa-email-notification" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-email-notification"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-email-notification
  tags = {
    Name      = "uplift-qa-email-notification"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-email-notification = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-email-notification.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}
# ## livestream_video
module "uplift-qa-livestream-video" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-livestream-video"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-livestream-video
  tags = {
    Name      = "uplift-qa-livestream-video"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-livestream-video = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-livestream-video.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}

# ## mint_trending
module "uplift-qa-mint-trending" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-mint-trending"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-mint-trending
  tags = {
    Name      = "uplift-qa-mint-trending"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-mint-trending = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-mint-trending.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}
# ## mint_worker_qa
module "uplift-qa-mint-worker" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-mint-worker"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-mint-worker
  tags = {
    Name      = "uplift-qa-mint-worker"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-mint-worker = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-mint-worker.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}

# ## qa-delete-users
module "uplift-qa-delete-users" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-delete-users"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-delete-users
  tags = {
    Name      = "uplift-qa-delete-users"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-delete-users = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-delete-users.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225","858651804942"]
        }
      ]
    }
  }
}
# ## qa_activity_cron.fifo
module "uplift-qa-activity-cron-fifo" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-activity-cron.fifo"

  fifo_queue                  = var.fifo_queue
  content_based_deduplication = var.content_based_deduplication
  sqs_managed_sse_enabled     = var.sqs_managed_sse_enabled
  create_queue_policy         = true
  queue_policy_statements     = local.uplift-qa-activity-cron-fifo
  tags = {
    Name      = "uplift-qa-activity-cron.fifo"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}
locals {
  uplift-qa-activity-cron-fifo = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-activity-cron-fifo.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}
# ## qa_activity_weekly_uplift
module "uplift-qa-activity-weekly" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-activity-weekly"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-activity-weekly
  tags = {
    Name      = "uplift-qa-activity-weekly"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-activity-weekly = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-activity-weekly.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}
# ## qa_api_fail_processor
module "uplift-qa-api-fail-processor" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-api-fail-processor"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-api-fail-processor
  tags = {
    Name      = "uplift-qa-api-fail-processor"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-api-fail-processor = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-api-fail-processor.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}
# ## qa_complimint_conversation
module "uplift-qa-complimint-conversation" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-complimint-conversation"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-complimint-conversation
  tags = {
    Name      = "uplift-qa-complimint-conversation"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-complimint-conversation = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-complimint-conversation.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}

# ## qa_daily_snapshot
module "uplift-qa-daily-snapshot" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-daily-snapshot"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-daily-snapshot
  tags = {
    Name      = "uplift-qa-daily-snapshot"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-daily-snapshot = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-daily-snapshot.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}
# ## qa_gamification
module "uplift-qa-gamification" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-gamification"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-gamification
  tags = {
    Name      = "uplift-qa-gamification"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-gamification = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-gamification.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}
## qa_gamification_notify.fifo
module "uplift-qa-gamification-notify-fifo" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-gamification-notify.fifo"

  fifo_queue                  = var.fifo_queue
  content_based_deduplication = var.content_based_deduplication
  sqs_managed_sse_enabled     = var.sqs_managed_sse_enabled
  create_queue_policy         = true
  queue_policy_statements     = local.uplift-qa-gamification-notify-fifo
  tags = {
    Name      = "uplift-qa-gamification-notify.fifo"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}
locals {
  uplift-qa-gamification-notify-fifo = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-gamification-notify-fifo.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}
# ## qa_image_compress_resize
module "uplift-qa-image-compress-resize" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-image-compress-resize"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-image-compress-resize
  tags = {
    Name      = "uplift-qa-image-compress-resize"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-image-compress-resize = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-image-compress-resize.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        },
        {
          type        = "Service"
          identifiers = ["s3.amazonaws.com"]
        }
      ]
    }
  }
}
# ## qa_inspiration_score
module "uplift-qa-inspiration-score" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-inspiration-score"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-inspiration-score
  tags = {
    Name      = "uplift-qa-inspiration-score"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-inspiration-score = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-inspiration-score.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}
# ## qa_ms_activity_getstream
module "uplift-qa-ms-activity-getstream" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-ms-activity-getstream"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-ms-activity-getstream
  tags = {
    Name      = "uplift-qa-ms-activity-getstream"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-ms-activity-getstream = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-ms-activity-getstream.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}
# ## recent_tagged_showrooms
module "uplift-qa-recent-tagged-showrooms" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-recent-tagged-showrooms"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-recent-tagged-showrooms
  tags = {
    Name      = "uplift-qa-recent-tagged-showrooms"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-recent-tagged-showrooms = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-recent-tagged-showrooms.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        },
        {
          type        = "Service"
          identifiers = ["sns.amazonaws.com"]
        }
      ]
    }
  }
}

# ## showroom_trending
module "uplift-qa-showroom-trending" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-showroom-trending"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-showroom-trending
  tags = {
    Name      = "uplift-qa-showroom-trending"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-showroom-trending = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-showroom-trending.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}
# ## upliftzone.fifo
module "uplift-qa-upliftzone-fifo" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-upliftzone.fifo"

  fifo_queue                  = var.fifo_queue
  content_based_deduplication = var.content_based_deduplication
  sqs_managed_sse_enabled     = var.sqs_managed_sse_enabled
  create_queue_policy         = true
  queue_policy_statements     = local.uplift-qa-upliftzone-fifo
  tags = {
    Name      = "uplift-qa-upliftzone.fifo"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}
locals {
  uplift-qa-upliftzone-fifo = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-upliftzone-fifo.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}
# ## videoservice
module "uplift-qa-video-service" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-video-service"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-video-service
  tags = {
    Name      = "uplift-qa-video-service"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-video-service = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-video-service.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}

# ## welcome_mint
module "uplift-qa-welcome-mint" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-welcome-mint"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-welcome-mint
  tags = {
    Name      = "uplift-qa-welcome-mint"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-welcome-mint = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-welcome-mint.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}
# ## zencoder_api
module "uplift-qa-zencoder-api" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-zencoder-api"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-zencoder-api
  tags = {
    Name      = "uplift-qa-zencoder-api"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-zencoder-api = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-zencoder-api.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        },
        {
          type        = "Service"
          identifiers = ["s3.amazonaws.com"]
        }
      ]
    }
  }
}
# ## firebase
module "uplift-qa-firebase" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-firebase"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-firebase
  tags = {
    Name      = "uplift-qa-firebase"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-firebase = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-firebase.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}
# ## requestworker
module "uplift-qa-request-worker" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-request-worker"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-request-worker
  tags = {
    Name      = "uplift-qa-request-worker"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-request-worker = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-request-worker.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}
# ## test.fifo
module "uplift-qa-test-fifo" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-test.fifo"

  fifo_queue                  = var.fifo_queue
  content_based_deduplication = var.content_based_deduplication
  sqs_managed_sse_enabled     = var.sqs_managed_sse_enabled
  create_queue_policy         = true
  queue_policy_statements     = local.uplift-qa-test-fifo
  tags = {
    Name      = "uplift-qa-test.fifo"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}
locals {
  uplift-qa-test-fifo = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-test-fifo.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}

# ## testEmail
module "uplift-qa-test-email" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-test-email"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-test-email
  tags = {
    Name      = "uplift-qa-test-email"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-test-email = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-test-email.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}
# ## socket-notification

module "uplift-qa-socket-notification" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1" # 4.0.2
  name    = "uplift-qa-socket-notification"

  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  create_queue_policy        = true
  queue_policy_statements    = local.uplift-qa-socket-notification
  tags = {
    Name      = "uplift-qa-socket-notification"
    Createdby = local.tags_sqs.Createdby
    Namespace = local.tags_sqs.Namespace
    Stage     = local.tags_sqs.Stage
  }

}

locals {
  uplift-qa-socket-notification = {
    account = {
      sid       = "Sid870012702952"
      actions   = ["sqs:*"]
      resources = [module.uplift-qa-socket-notification.queue_arn]
      principals = [
        {
          type        = "AWS"
          identifiers = ["332923349225"]
        }
      ]
    }
  }
}

# #####################################################################
# ## S3 bucket
# #####################################################################
# ## mintshow-category-qa
module "s3_bucket_uplift_qa_category" {
  source  = "cloudposse/s3-bucket/aws"
  version = "4.10.0" # 4.0.0
  name    = "s3-bucket"

  user_enabled                  = var.user_enabled
  acl                           = var.public_read_acl
  block_public_acls             = var.public_block_public_acls
  block_public_policy           = var.public_block_public_policy
  ignore_public_acls            = var.public_ignore_public_acls
  restrict_public_buckets       = var.public_restrict_public_buckets
  force_destroy                 = var.force_destroy
  versioning_enabled            = var.versioning_enabled
  bucket_name                   = var.qa_category
  privileged_principal_actions  = var.privileged_principal_actions
  transfer_acceleration_enabled = var.transfer_acceleration_enabled

  context = module.label.context
}

module "s3_bucket_uplift_qa_images" {
  source  = "cloudposse/s3-bucket/aws"
  version = "4.10.0" # 4.0.0
  name    = "s3-bucket"

  user_enabled                  = var.user_enabled
  acl                           = var.public_read_acl
  block_public_acls             = var.public_block_public_acls
  block_public_policy           = var.public_block_public_policy
  ignore_public_acls            = var.public_ignore_public_acls
  restrict_public_buckets       = var.public_restrict_public_buckets
  force_destroy                 = var.force_destroy
  versioning_enabled            = var.versioning_enabled
  bucket_name                   = var.qa_images
  privileged_principal_actions  = var.privileged_principal_actions
  transfer_acceleration_enabled = var.transfer_acceleration_enabled

  context = module.label.context
}

module "s3_bucket_uplift_qa_videos" {
  source  = "cloudposse/s3-bucket/aws"
  version = "4.10.0" # 4.0.0
  name    = "s3-bucket"

  user_enabled                  = var.user_enabled
  acl                           = var.public_read_acl
  block_public_acls             = var.public_block_public_acls
  block_public_policy           = var.public_block_public_policy
  ignore_public_acls            = var.public_ignore_public_acls
  restrict_public_buckets       = var.public_restrict_public_buckets
  force_destroy                 = var.force_destroy
  versioning_enabled            = var.versioning_enabled
  bucket_name                   = var.qa_videos
  privileged_principal_actions  = var.privileged_principal_actions
  transfer_acceleration_enabled = var.transfer_acceleration_enabled

  context = module.label.context
}
module "s3_bucket_uplift_qa_admin" {
  source  = "cloudposse/s3-bucket/aws"
  version = "4.10.0" # 4.0.0
  name    = "s3-bucket"

  user_enabled                  = var.user_enabled
  acl                           = var.public_read_acl
  block_public_acls             = var.public_block_public_acls
  block_public_policy           = var.public_block_public_policy
  ignore_public_acls            = var.public_ignore_public_acls
  restrict_public_buckets       = var.public_restrict_public_buckets
  force_destroy                 = var.force_destroy
  versioning_enabled            = var.versioning_enabled
  bucket_name                   = var.qa_admin
  privileged_principal_actions  = var.privileged_principal_actions
  transfer_acceleration_enabled = var.transfer_acceleration_enabled

  context = module.label.context
}
module "s3_bucket_uplift_qa_assets" {
  source  = "cloudposse/s3-bucket/aws"
  version = "4.10.0" # 4.0.0
  name    = "assets"

  user_enabled                  = var.user_enabled
  acl                           = var.public_read_acl
  block_public_acls             = var.public_block_public_acls
  block_public_policy           = var.public_block_public_policy
  ignore_public_acls            = var.public_ignore_public_acls
  restrict_public_buckets       = var.public_restrict_public_buckets
  force_destroy                 = var.force_destroy
  versioning_enabled            = var.versioning_enabled
  bucket_name                   = var.qa_assets
  privileged_principal_actions  = var.privileged_principal_actions
  transfer_acceleration_enabled = var.transfer_acceleration_enabled

  context = module.label.context
}

# #####################################################################
# ## Transit Gateway qa 
# #####################################################################
locals {
  name = "transit-gateway"
  tags = {
    "Createdby" = var.createdby
    namespace   = var.namespace
    stage       = var.stage

  }
}
module "tgw_peer" {
  # This is optional and connects to another account. Meaning you need to be authenticated with 2 separate AWS Accounts
  source                 = "terraform-aws-modules/transit-gateway/aws"
  version                = "2.12.2" # "2.13.0"
  name                   = "${local.name}-peer"
  description            = "My TGW shared with several other AWS accounts"
  amazon_side_asn        = var.amazon_side_asn
  create_tgw             = var.create_tgw
  share_tgw              = var.share_tgw
  ram_resource_share_arn = var.resource_share_arn
  # When "true" there is no need for RAM resources if using multiple AWS accounts
  enable_auto_accept_shared_attachments = var.enable_auto_accept_shared_attachments
  vpc_attachments = {
    qa = {
      tgw_id       = var.transit_gateway_id
      vpc_id       = sensitive(module.vpc.vpc_id)
      subnet_ids   = module.subnets.private_subnet_ids
      dns_support  = var.dns_support
      ipv6_support = var.ipv6_support
      #enable_sg_referencing_support = var.enable_sg_referencing_support 
      transit_gateway_default_route_table_association = var.route_table_association
      transit_gateway_default_route_table_propagation = var.route_table_propagation
      tgw_routes = [
        {
          destination_cidr_block = var.destination_cidr_block
        }
      ]
    }
  }
  ram_allow_external_principals = var.ram_allow_external_principals
  ram_principals                = var.ram_principals
  tags                          = local.tags
}
# #####################################################################
# ## Transit Gateway Route
# #####################################################################
module "route_entry" {
  source                 = "../bsetec/route_record"
  name                   = "route-table-entry"
  vpc_id                 = sensitive(module.vpc.vpc_id)
  destination_cidr_block = ["10.0.0.0/16"]
  transit_gateway_id     = var.transit_gateway_id
  module_depends_on      = module.tgw_peer.ec2_transit_gateway_id

  context = module.label.context
}
#####################################################################
## Waf
#####################################################################
module "waf" {
  source         = "cloudposse/waf/aws"
  version        = "1.8.0" # 1.2.0
  name           = "waf"
  default_action = var.allow_default_action
  enabled        = var.waf_enabled
  scope          = var.waf_scope
  # association_resource_arns = [module.alb.alb_arn]
  context = module.label.context

  rate_based_statement_rules = [
    {
      name     = "rate-limit-rule"
      priority = "1"
      action   = "block"

      statement = {
        limit              = 2000
        aggregate_key_type = "IP"
      }
      visibility_config = {
        cloudwatch_metrics_enabled = true
        metric_name                = "rate-limit-rule"
        sampled_requests_enabled   = true
      }
    }
  ]

  managed_rule_group_statement_rules = [
    {
      name            = "AWSManagedRulesAmazonIpReputationList"
      override_action = "none"
      priority        = 2

      statement = {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }

      visibility_config = {
        cloudwatch_metrics_enabled = true
        sampled_requests_enabled   = true
        metric_name                = "AWSManagedRulesAmazonIpReputationList-metric"
      }
    },
    {
      name            = "AWSManagedRulesAnonymousIpList"
      override_action = "none"
      priority        = 3

      statement = {
        name        = "AWSManagedRulesAnonymousIpList"
        vendor_name = "AWS"
      }

      visibility_config = {
        cloudwatch_metrics_enabled = true
        sampled_requests_enabled   = true
        metric_name                = "AWSManagedRulesAnonymousIpList-metric"
      }
    }
  ]
  visibility_config = {
    cloudwatch_metrics_enabled = true
    metric_name                = "uplift-qa-waf"
    sampled_requests_enabled   = true
  }
}
#   ip_set_reference_statement_rules = [
#     {
#       name     = "allow-ip-set-rule"
#       priority = "0"
#       action   = "allow"

#       statement = {
#         arn = module.ip_set.ip_set_arn
#       }
#       visibility_config = {
#         cloudwatch_metrics_enabled = true
#         metric_name                = "qa-waf-ip-set-block-metrics"
#         sampled_requests_enabled   = true
#       }
#     }
#   ]
# }

# module "ip_set" {
#   source       = "../bsetec/waf"
#   name         = "waf-ip-set"
#   namespace    = var.namespace
#   createdby    = var.createdby
#   stage        = var.stage
#   ip_addresses = var.ip_addresses
#   context      = module.label.context

# }
####################################################################
# Aurora
####################################################################
# module "rds_cluster_aurora_mysql" {
#   source  = "cloudposse/rds-cluster/aws"
#   version = "1.9.0" # 1.9.0

#   name   = "mysql"
#   engine = var.engine
#   # engine_mode                          = var.engine_mode
#   # cluster_family                       = var.cluster_family
#   cluster_family    = "aurora-mysql5.7"
#   cluster_size      = var.replica_count
#   admin_user        = var.username
#   admin_password    = var.admin_password
#   db_name           = var.db_name
#   instance_type     = var.instance_type
#   vpc_id            = sensitive(module.vpc.vpc_id)
#   subnets           = module.subnets.private_subnet_ids
#   security_groups   = [module.vpc.vpc_default_security_group_id]
#   storage_encrypted = var.storage_encrypted
#   kms_key_arn       = module.aws_kms_key_mysql.key_arn
#   # replica_count                       = var.replica_count
#   deletion_protection                 = var.deletion_protection
#   apply_immediately                   = var.apply_immediately
#   publicly_accessible                 = var.publicly_accessible
#   enabled_cloudwatch_logs_exports     = var.enabled_cloudwatch_logs_exports
#   iam_database_authentication_enabled = var.iam_database_authentication_enabled
#   rds_monitoring_interval             = var.monitoring_interval
#   # autoscaling_enabled                  = var.autoscaling_enabled
#   # storage_type                         = var.storage_type
#   # iops                                 = var.iops
#   # allocated_storage                    = var.allocated_storage
#   # intra_security_group_traffic_enabled = var.intra_security_group_traffic_enabled

#   # cluster_parameters = [
#   #   {
#   #     name         = "character_set_client"
#   #     value        = "utf8"
#   #     apply_method = "pending-reboot"
#   #   },
#   #   {
#   #     name         = "character_set_connection"
#   #     value        = "utf8"
#   #     apply_method = "pending-reboot"
#   #   },
#   #   {
#   #     name         = "character_set_database"
#   #     value        = "utf8"
#   #     apply_method = "pending-reboot"
#   #   },
#   #   {
#   #     name         = "character_set_results"
#   #     value        = "utf8"
#   #     apply_method = "pending-reboot"
#   #   },
#   #   {
#   #     name         = "character_set_server"
#   #     value        = "utf8"
#   #     apply_method = "pending-reboot"
#   #   },
#   #   {
#   #     name         = "collation_connection"
#   #     value        = "utf8_bin"
#   #     apply_method = "pending-reboot"
#   #   },
#   #   {
#   #     name         = "collation_server"
#   #     value        = "utf8_bin"
#   #     apply_method = "pending-reboot"
#   #   },
#   #   {
#   #     name         = "lower_case_table_names"
#   #     value        = "1"
#   #     apply_method = "pending-reboot"
#   #   },
#   #   {
#   #     name         = "skip-character-set-client-handshake"
#   #     value        = "1"
#   #     apply_method = "pending-reboot"
#   #   }
#   # ]

#   context = module.label.context
# }
# #####################################################################
# ## KMS
# #####################################################################
module "aws_kms_key_mysql" {
  source      = "cloudposse/kms-key/aws"
  version     = "0.12.2" # 0.12.1
  name        = "kms"
  description = "KMS key for Rds mysql"

  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = var.enable_key_rotation
  alias                   = "alias/ec2-instance"
  policy                  = data.aws_iam_policy_document.kms_mysql_document.json
  context                 = module.label.context
}

data "aws_iam_policy_document" "kms_mysql_document" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

}
#####################################################################
## EFS
#####################################################################
module "efs" {
  source = "../bsetec/efs-1.2.0"

  name   = "efs"
  region = var.region

  subnets = module.subnets.public_subnet_ids

  vpc_id = sensitive(module.vpc.vpc_id)

  security_groups           = [module.vpc.vpc_default_security_group_id]
  efs_backup_policy_enabled = var.efs_backup_policy_enabled
  allowed_cidr_blocks       = var.efs_allow_cidr

  context = module.label.context

}
# #####################################################################
# ## KMS
# #####################################################################
module "aws_kms_key" {
  source      = "cloudposse/kms-key/aws"
  version     = "0.12.2" # 0.12.1
  name        = "kms"
  description = "KMS key for chamber"

  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = var.enable_key_rotation
  alias                   = "alias/ec2-intance"
  policy                  = data.aws_iam_policy_document.kms_document.json
  context                 = module.label.context
}

data "aws_iam_policy_document" "kms_document" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

}
###############################################################################
### Load balancer
###############################################################################
module "antmedia_alb" {
  source  = "cloudposse/alb/aws"
  version = "2.3.0" # 1.11.1

  stage = var.stage
  name  = "antmedia-alb"

  vpc_id              = sensitive(module.vpc.vpc_id)
  security_group_ids  = [module.ssh.id, module.http-https.id]
  subnet_ids          = module.subnets.public_subnet_ids
  internal            = false
  http_enabled        = true
  https_enabled       = true
  http_redirect       = false
  access_logs_enabled = false
  https_ssl_policy    = "ELBSecurityPolicy-2015-05"
  # cross_zone_load_balancing_enabled = var.cross_zone_load_balancing_enabled
  http2_enabled                    = true
  idle_timeout                     = 10
  ip_address_type                  = "ipv4"
  deletion_protection_enabled      = true
  deregistration_delay             = 300
  health_check_path                = "/"
  health_check_timeout             = 10
  health_check_healthy_threshold   = 3
  health_check_unhealthy_threshold = 3
  health_check_interval            = 30
  health_check_matcher             = "200-399"
  target_group_port                = 5080
  target_group_target_type         = "instance"
  # stickiness                        = var.stickiness
  https_port      = 443
  certificate_arn = module.acm.arn

  # alb_access_logs_s3_bucket_force_destroy         = var.alb_access_logs_s3_bucket_force_destroy
  # alb_access_logs_s3_bucket_force_destroy_enabled = var.alb_access_logs_s3_bucket_force_destroy_enabled

  # tags = var.tags
  context = module.label.context
}
# #####################################################################
# ## Ec2 Instance Creation for antmedia
# #####################################################################

# module "aws_antmedia_instance" {
#   source = "../bsetec/ec2-instance-group"
#   name   = "antmedia"

#   # Instance Configurations
#   region                  = var.region
#   ami_owner               = var.ami_owner
#   ami                     = var.ec2_ami
#   instance_type           = var.ec2_instance_type
#   instance_count          = 1
#   monitoring              = false
#   disable_api_termination = true

#   # Key pair configurations
#   ssh_key_pair = module.key_pair.key_name

#   # Vpc configurations
#   vpc_id                 = sensitive(module.vpc.vpc_id)
#   subnet                 = tolist(module.subnets.public_subnet_ids)
#   security_groups        = [module.antmedia.id]
#   security_group_enabled = false
#   private_ips            = []

#   # Ip configurations
#   assign_eip_address          = var.assign_eip_address
#   associate_public_ip_address = var.associate_public_ip_address

#   #EBS configurations  
#   root_volume_type      = "gp3"
#   root_volume_size      = 100
#   root_iops             = "3000"
#   delete_on_termination = true
#   kms_key_id            = module.aws_kms_key.key_arn

#   context = module.label.context
# }
#####################################################################
## Cognito
#####################################################################

module "cognito-identity-pool" {
  source = "../bsetec/cognito-identity"

  identity_pool_name               = var.identity_pool_name
  allow_unauthenticated_identities = var.allow_unauthenticated_identities
  authenticated_role_name          = "uplift-qa-cognito-authenticated-role"
  authenticated_role_policy        = "uplift-qa-cognito-authenticated-policy"
  unauthenticated_role_name        = "uplift-qa-cognito-unauthenticated-role"
  unauthenticated_role_policy      = "uplift-qa-cognito-unauthenticated-policy"

}
#####################################################################
## sns
#####################################################################
locals {
  tags_sns = {
    Createdby = var.createdby
    namespace = var.namespace
    stage     = var.stage

  }
}
locals {
  delivery_policy = jsonencode({
    "http" : {
      "defaultHealthyRetryPolicy" : {
        "minDelayTarget" : 20,
        "maxDelayTarget" : 20,
        "numRetries" : 3,
        "numMaxDelayRetries" : 0,
        "numNoDelayRetries" : 0,
        "numMinDelayRetries" : 0,
        "backoffFunction" : "linear"
      },
      "disableSubscriptionOverrides" : false,
      "defaultThrottlePolicy" : {
        "maxReceivesPerSecond" : 1
      }
    }
  })
}
module "sns_new_mint_notifications" {
  source  = "terraform-aws-modules/sns/aws"
  version = "6.2.0" # 6.0.1

  name                        = var.new_mint_notification
  display_name                = var.new_mint_notification
  use_name_prefix             = var.use_name_prefix
  delivery_policy             = local.delivery_policy
  create_topic_policy         = var.create_topic_policy
  enable_default_topic_policy = var.enable_default_topic_policy
  topic_policy_statements     = var.topic_policy_statements
  subscriptions               = var.new_mint_notification_subscriptions

  tags = {
    Name      = var.new_mint_notification
    Createdby = local.tags_sns.Createdby
    namespace = local.tags_sns.namespace
    stage     = local.tags_sns.stage
  }
}

module "sns_solr_import" {
  source  = "terraform-aws-modules/sns/aws"
  version = "6.2.0" # 6.0.1

  name                        = var.solr_import
  display_name                = var.solr_import
  use_name_prefix             = var.use_name_prefix
  delivery_policy             = local.delivery_policy
  create_topic_policy         = var.create_topic_policy
  enable_default_topic_policy = var.enable_default_topic_policy
  topic_policy_statements     = var.topic_policy_statements
  subscriptions               = var.solr_import_subscriptions

  tags = {
    Name      = var.solr_import
    Createdby = local.tags_sns.Createdby
    namespace = local.tags_sns.namespace
    stage     = local.tags_sns.stage
  }
}

module "sns_tag_showrooms" {
  source  = "terraform-aws-modules/sns/aws"
  version = "6.2.0" # 6.0.1

  name                        = var.tag_showrooms
  display_name                = var.tag_showrooms
  use_name_prefix             = var.use_name_prefix
  delivery_policy             = local.delivery_policy
  create_topic_policy         = var.create_topic_policy
  enable_default_topic_policy = var.enable_default_topic_policy
  topic_policy_statements     = var.topic_policy_statements
  subscriptions               = var.tag_showrooms_subscriptions

  tags = {
    Name      = var.tag_showrooms
    Createdby = local.tags_sns.Createdby
    namespace = local.tags_sns.namespace
    stage     = local.tags_sns.stage
  }
}

#####################################################################
## Elasticcache - redis
#####################################################################
module "cloudwatch_logs_qa_redis_slowlog" {
  source            = "cloudposse/cloudwatch-logs/aws"
  version           = "0.6.9" # 0.6.8
  name              = "redis-slow"
  stage             = "qa"
  retention_in_days = "14"
  context           = module.label.context
}

module "cloudwatch_logs_qa_redis_enginelog" {
  source            = "cloudposse/cloudwatch-logs/aws"
  version           = "0.6.9" # 0.6.8
  name              = "redis-engine"
  stage             = "qa"
  retention_in_days = "14"
  context           = module.label.context
}

module "redis" {
  source  = "cloudposse/elasticache-redis/aws"
  version = "1.9.1" # 0.52.0
  name    = "redis"
  stage   = "qa"

  # availability_zones         = var.redis_availability_zones
  vpc_id                     = sensitive(module.vpc.vpc_id)
  allowed_security_group_ids = [module.redis-sg.id]
  subnets                    = module.subnets.private_subnet_ids
  cluster_size               = 1
  instance_type              = var.redis_node_type
  apply_immediately          = true
  automatic_failover_enabled = false
  engine_version             = var.redis_engine_version
  family                     = var.redis_parameter_group_name
  snapshot_arns              = var.snapshot_arns
  snapshot_retention_limit   = 10
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = var.auth_token
  user_group_ids             = null
  parameter_group_name = var.parameter_group_name_redis
  parameter_group_description = var.parameter_group_description
  security_group_create_before_destroy = true
  parameter = [
    {
      name  = "notify-keyspace-events"
      value = "lK"
    }
  ]

  log_delivery_configuration = [
    {
      destination      = module.cloudwatch_logs_qa_redis_slowlog.log_group_name
      destination_type = "cloudwatch-logs"
      log_format       = "json"
      log_type         = "slow-log"
    },
    {
      destination      = module.cloudwatch_logs_qa_redis_enginelog.log_group_name
      destination_type = "cloudwatch-logs"
      log_format       = "json"
      log_type         = "engine-log"
    }
  ]

  context = module.label.context
}

#####################################################################
## Elasticcache - redis trending
#####################################################################
# module "cloudwatch_logs_qa_trending_redis_slowlog" {
#   source            = "cloudposse/cloudwatch-logs/aws"
#   version           = "0.6.9" # 0.6.8
#   name              = "trending-redis-slow"
#   stage             = "qa"
#   retention_in_days = "14"
#   context           = module.label.context
# }

# module "cloudwatch_logs_qa_trending_redis_enginelog" {
#   source            = "cloudposse/cloudwatch-logs/aws"
#   version           = "0.6.9" # 0.6.8
#   name              = "trending-redis-engine"
#   stage             = "qa"
#   retention_in_days = "14"
#   context           = module.label.context
# }

# module "redis_trending" {
#   source  = "cloudposse/elasticache-redis/aws"
#   version = "0.52.0"
#   name    = "trending-redis"
#   stage   = "qa"

#   # availability_zones         = var.redis_availability_zones
#   vpc_id                     = sensitive(module.vpc.vpc_id)
#   allowed_security_group_ids = [module.redis-sg-new.id]
#   subnets                    = module.subnets.private_subnet_ids
#   cluster_size               = 1
#   instance_type              = var.redis_node_type
#   apply_immediately          = true
#   automatic_failover_enabled = false
#   engine_version             = "7.0"
#   family                     = var.redis_parameter_group_name
#   snapshot_arns              = var.snapshot_arns_trending
#   snapshot_retention_limit   = 10
#   at_rest_encryption_enabled = true
#   transit_encryption_enabled = true
#   auth_token                 = var.auth_token_trending
#   user_group_ids             = null

#   parameter = [
#     {
#       name  = "notify-keyspace-events"
#       value = "lK"
#     }
#   ]

#   log_delivery_configuration = [
#     {
#       destination      = module.cloudwatch_logs_qa_trending_redis_slowlog.log_group_name
#       destination_type = "cloudwatch-logs"
#       log_format       = "json"
#       log_type         = "slow-log"
#     },
#     {
#       destination      = module.cloudwatch_logs_qa_trending_redis_enginelog.log_group_name
#       destination_type = "cloudwatch-logs"
#       log_format       = "json"
#       log_type         = "engine-log"
#     }
#   ]

#   context = module.label.context
# }
#####################################################################
## Elasticcache - redis-trending-new
#####################################################################
module "cloudwatch_logs_qa_trending_redis_new_slowlog" {
  source            = "cloudposse/cloudwatch-logs/aws"
  version           = "0.6.9" # 0.6.8
  name              = "trending-redis-new-slow"
  stage             = "qa"
  retention_in_days = "14"
  context           = module.label.context
}

module "cloudwatch_logs_qa_trending_redis_new_enginelog" {
  source            = "cloudposse/cloudwatch-logs/aws"
  version           = "0.6.9" # 0.6.8
  name              = "trending-redis-new-engine"
  stage             = "qa"
  retention_in_days = "14"
  context           = module.label.context
}

module "redis_trending_new" {
  source  = "cloudposse/elasticache-redis/aws"
  version = "1.9.2"
  name    = "trending-redis-new"
  stage   = "qa"

  # availability_zones         = var.redis_availability_zones
  vpc_id                     = sensitive(module.vpc.vpc_id)
  allowed_security_group_ids = [module.redis-sg-new.id]
  subnets                    = module.subnets.private_subnet_ids
  cluster_size               = 1
  instance_type              = var.redis_node_type
  apply_immediately          = true
  automatic_failover_enabled = false
  engine_version             = var.redis_engine_version
  family                     = var.redis_parameter_group_name
  snapshot_arns              = var.snapshot_arns_trending_new
  snapshot_retention_limit   = 10
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = var.auth_token_trending
  user_group_ids             = null
  parameter_group_name = var.parameter_group_name_redis_trending
  parameter_group_description = var.parameter_group_description
  security_group_create_before_destroy = true
  parameter = [
    {
      name  = "notify-keyspace-events"
      value = "lK"
    }
  ]

  log_delivery_configuration = [
    {
      destination      = module.cloudwatch_logs_qa_trending_redis_new_slowlog.log_group_name
      destination_type = "cloudwatch-logs"
      log_format       = "json"
      log_type         = "slow-log"
    },
    {
      destination      = module.cloudwatch_logs_qa_trending_redis_new_enginelog.log_group_name
      destination_type = "cloudwatch-logs"
      log_format       = "json"
      log_type         = "engine-log"
    }
  ]

  context = module.label.context
}
#####################################################################
## Cloudfront - S3 bucket
#####################################################################
module "cloudfront-s3-cdn-assets" {
  source  = "terraform-module/cloudfront/aws"
  version = "1.1.1"

  s3_origin_config = [{
    domain_name = module.s3_bucket_uplift_qa_assets.bucket_regional_domain_name
  }]
  aliases = ["assets.qa.liveuplift.com"]
  viewer_certificate = {
    acm_certificate_arn = module.acm.arn
    ssl_support_method  = "sni-only"
  }
  default_cache_behavior = {
    min_ttl                    = 1000
    default_ttl                = 1000
    max_ttl                    = 1000
    cookies_forward            = "none"
    response_headers_policy_id = "Managed-SecurityHeadersPolicy"
    headers = [
      "Origin",
      "Access-Control-Request-Headers",
      "Access-Control-Request-Method"
    ]
  }

}
######################################################################
#sg
######################################################################
module "sg-rds" {
  source  = "cloudposse/security-group/aws"
  version = "2.2.0"
  name   = "sg-rds"

  # Allow unlimited egress
  allow_all_egress = true

  rules = [
    {
      key         = "ssh"
      type        = "ingress"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "0.0.0.0/0"]
      self        = null
    }
  ]
  # create_before_destroy	=false
  # preserve_security_group_id=true
  vpc_id  = sensitive(module.vpc.vpc_id)
  context = module.label.context
}
####################################################################
############ec2-rds
####################################################################
module "EC2-rds"{
  source  = "../bsetec/ec2-instance-group"
  name   = "ec2-rds"

  # Instance Configurations
  region                  = var.region
  ami_owner               = "099720109477"
  ami                     = "ami-04a81a99f5ec58529"
  instance_type           = "t3.medium"
  instance_count          = 1
  monitoring              = false
  disable_api_termination = true

  # Key pair configurations
  ssh_key_pair = module.key_pair.key_name

  # Vpc configurations
  vpc_id                 = sensitive(module.vpc.vpc_id)
  subnet                 = tolist(module.subnets.public_subnet_ids)
  security_groups        = [module.sg-rds.id]
  security_group_enabled = false
  private_ips            = []

  # Ip configurations
  assign_eip_address          = var.assign_eip_address
  associate_public_ip_address = var.associate_public_ip_address

  #EBS configurations  
  root_volume_type      = "gp3"
  root_volume_size      = 10
  root_iops             = "3000"
  delete_on_termination = true
  kms_key_id            = module.aws_kms_key.key_arn

  context = module.label.context
}
####################################################################
#rds-cluster
######################################################################
module "rds_aurora_mysql" {
  source  = "cloudposse/rds-cluster/aws"
  version = "2.1.0" # 1.11.1

  name   = "aurora-mysql-8"
  engine = var.engine
  engine_version = "8.0.mysql_aurora.3.08.2"
  cluster_family    = "aurora-mysql8.0"
  cluster_size      = var.replica_count
  admin_user        = var.username
  admin_password    = var.admin_password
  db_name           = var.db_name
  instance_type     = var.instance_type
  vpc_id            = sensitive(module.vpc.vpc_id)
  subnets           = module.subnets.private_subnet_ids
  security_groups   = [module.vpc.vpc_default_security_group_id]
  storage_encrypted = var.storage_encrypted
  kms_key_arn       = module.aws_kms_key_mysql.key_arn

  deletion_protection                 = var.deletion_protection
  apply_immediately                   = var.apply_immediately
  publicly_accessible                 = var.publicly_accessible
  enabled_cloudwatch_logs_exports     = var.enabled_cloudwatch_logs_exports
  iam_database_authentication_enabled = var.iam_database_authentication_enabled
  rds_monitoring_interval             = var.monitoring_interval

  # ✅ Add the time zone parameter *inside* the module
  cluster_parameters = [
    {
     name         = "time_zone"
     value        = "US/Central"
     apply_method = "immediate"
    }
  ]

  context = module.label.context
}
#####################################################################
 #####################################################################
# ## Ec2 Instance Creation for antmedia
# #####################################################################

module "aws_antmedia_instance" {
  source = "../bsetec/ec2-instance-group-1.0.0" #"../bsetec/ec2-instance-group" 
  name   = "antmedia"

  # Instance Configurations
  region                  = var.region
  ami_owner               = var.ami_owner
  ami                     = var.ec2_ami
  instance_type           = var.ec2_instance_type
  instance_count          = 1
  monitoring              = false
  disable_api_termination = true

  
  # Key pair configurations
  ssh_key_pair = module.key_pair.key_name

  # Vpc configurations
  vpc_id                 = sensitive(module.vpc.vpc_id)
  subnet                 = tolist(module.subnets.public_subnet_ids)
  security_groups        = [module.antmedia-sg.id]
  security_group_enabled = false
  private_ips            = []

  # Ip configurations
  assign_eip_address          = var.assign_eip_address
  associate_public_ip_address = var.associate_public_ip_address
  # ipv6_address_count          = var.ipv6_address_count
  # ipv6_addresses              = var.ipv6_addresses

  #EBS configurations  
  root_volume_type      = "gp3"
  root_volume_size      = 50
  root_iops             = "3000"
  delete_on_termination = true
  kms_key_id            = module.aws_kms_key.key_arn

  context = module.label.context
}

## Security Group - mongo db
module "antmedia-sg" {
  source  = "cloudposse/security-group/aws"
  version = "2.2.0"

  name = "sg-antmedia-new-qa"

  # Allow unlimited egress
  allow_all_egress = true

  rules = [
    {
      key         = "antmedia"
      type        = "ingress"
      from_port   = 27017
      to_port     = 27017
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block, "10.0.0.0/16" ]
      self        = null
      }, {
      key         = "ssh"
      type        = "ingress"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      self        = null
      }, {
      key         = "antmedia-tcp"
      type        = "ingress"
      from_port   = 5080
      to_port     = 5080
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      self        = null
      }, {
      key         = "antmedia-udp"
      type        = "ingress"
      from_port   = 5000
      to_port     = 65000
      protocol    = "udp"
      cidr_blocks = ["0.0.0.0/0"]
      self        = null
    }, {
      key         = "http"
      type        = "ingress"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      self        = null
    }, {
      key         = "https"
      type        = "ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      self        = null
    }
  ]

  vpc_id = sensitive(module.vpc.vpc_id)

  context = module.label.context
}
