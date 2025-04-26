data "aws_availability_zones" "available" {}

locals {
  available_zones = slice(
    data.aws_availability_zones.available.names,
    0,
    length(var.subnet_cidr_blocks)
  )
}

resource "aws_subnet" "subnets" {
  count = length(var.subnet_cidr_blocks)

  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = var.subnet_cidr_blocks[count.index]
  ipv6_cidr_block         = cidrsubnet(aws_vpc.main_vpc.ipv6_cidr_block, 8, count.index)
  availability_zone       = local.available_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.vpc_name}-subnet-${count.index + 1}"
  }
}
