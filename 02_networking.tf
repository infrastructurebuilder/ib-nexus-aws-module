
# ==============================================================================
# 2. NETWORKING (NAT GATEWAY & ROUTING)
# ==============================================================================

resource "aws_eip" "nat_eip" {
  count  = var.manage_private_routing ? 1 : 0
  domain = "vpc"

  tags = {
    Name   = "${var.name_prefix}-nat-eip"
    system = "nexus"
  }
}

resource "aws_nat_gateway" "nexus_nat" {
  count         = var.manage_private_routing ? 1 : 0
  allocation_id = aws_eip.nat_eip[0].id
  subnet_id     = data.aws_subnets.public.ids[0]

  tags = {
    Name   = "${var.name_prefix}-nat-gateway"
    system = "nexus"
  }
}

resource "aws_route_table" "private_rt" {
  count  = var.manage_private_routing ? 1 : 0
  vpc_id = data.aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nexus_nat[0].id
  }

  tags = {
    Name   = "${var.name_prefix}-private-route-table"
    system = "nexus"
  }
}

# Associate only the subnet the Nexus instance actually lives in, rather than
# every private subnet in the VPC — avoids hijacking egress routing for other
# workloads in a shared VPC.
resource "aws_route_table_association" "private_rt_assoc" {
  count          = var.manage_private_routing ? 1 : 0
  subnet_id      = local.sorted_subnet_ids[0]
  route_table_id = aws_route_table.private_rt[0].id
}
