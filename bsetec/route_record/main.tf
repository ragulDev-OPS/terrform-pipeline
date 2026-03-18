data "aws_subnets" "main" {
  /* vpc_id = var.vpc_id */
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

data "aws_route_tables" "main" {
  vpc_id = var.vpc_id
}

#Module      : AWS ROUTE
#Description : Provides a resource to create a routing table entry (a route) in a VPC routing table.
resource "aws_route" "main" {
  count = length(distinct(sort(data.aws_route_tables.main.ids))) * length(var.destination_cidr_block)

  route_table_id         = element(distinct(sort(data.aws_route_tables.main.ids)), count.index)
  destination_cidr_block = element(distinct(sort(var.destination_cidr_block)), ceil(count.index / length(var.destination_cidr_block), ), )
  transit_gateway_id     = var.transit_gateway_id
  depends_on = [
    data.aws_route_tables.main,
    data.aws_subnets.main,
    var.module_depends_on
  ]
}