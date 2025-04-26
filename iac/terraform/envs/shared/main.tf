module "network" {
  source = "../../modules/network"

  vpc_cidr              = "10.0.0.0/16"
  assign_generated_ipv6 = true
  enable_dns_support    = true
  enable_dns_hostnames  = true
  vpc_name              = "Main VPC"
}
