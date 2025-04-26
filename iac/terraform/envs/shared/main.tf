# Create VPC and network common infrastructure
module "network" {
  source = "../../modules/network"

  vpc_cidr              = "10.0.0.0/16"
  assign_generated_ipv6 = true
  enable_dns_support    = true
  enable_dns_hostnames  = true
  vpc_name              = "Main VPC"

  subnet_cidr_blocks = [
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24"
  ]
}
