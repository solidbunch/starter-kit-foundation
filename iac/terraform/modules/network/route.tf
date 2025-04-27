# Terraform module to create a route table and associate it with subnets in a VPC.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main_vpc.id
}

# This will create a route table for the VPC
resource "aws_route_table" "main_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.main.id
  }
}

# This will create a route table association for each subnet in the list
resource "aws_route_table_association" "main_associations" {
  for_each       = { for idx, subnet in aws_subnet.subnets : idx => subnet }
  subnet_id      = each.value.id
  route_table_id = aws_route_table.main_route_table.id
}
