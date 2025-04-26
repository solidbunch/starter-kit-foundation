resource "aws_vpc" "main_vpc" {
  cidr_block                       = var.vpc_cidr
  assign_generated_ipv6_cidr_block = var.assign_generated_ipv6
  enable_dns_support               = var.enable_dns_support
  enable_dns_hostnames             = var.enable_dns_hostnames

  tags = {
    Name = var.vpc_name
  }
}
