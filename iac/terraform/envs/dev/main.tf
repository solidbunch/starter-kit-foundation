# Create VPC and network infrastructure
module "network" {
  source   = "../../modules/network"
  vpc_cidr = var.vpc_cidr
}

# Create security groups
module "security_groups" {
  source = "../../modules/security_groups"
}

# Launch EC2 instances
module "instances" {
  source             = "../../modules/instances"

  instance_ami       = "ami-04bd057ffbd865312"                          # Debian 12 (HVM), arm64, SSD Volume Type, user 'admin', become 'sudo'
  instance_type      = "t4g.nano"                                       # 500MB RAM, 2 CPU, 8GB EBS
  public_key_name    = "id-rsa-starter-kit-deploy"                      # Name of the SSH public key
  public_key_path    = "./public_keys/id_rsa_starter_kit_deploy.pub"    # Path to the public SSH key file
  security_group_ids = [
    module.security_groups.allow_http_s_id,
    module.security_groups.allow_ssh_id
  ]
  tags = {
    Name        = "develop.starter-kit.io"
    Environment = "DEV"
  }
}
