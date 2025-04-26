# Fetch VPC and subnets from shared network
data "terraform_remote_state" "shared" {
  backend = "s3"
  config = {
    bucket = "starter-kit-io-terraform-state-storage"
    key    = "envs/shared/network.tfstate"
    region = "eu-west-1"
  }
}

# Create security groups
module "security_groups" {
  source = "../../modules/security_groups"
}

# Launch EC2 instances
module "instances" {
  source = "../../modules/instances"

  # Instance configuration
  instance_ami                         = "ami-04bd057ffbd865312"                          # Debian 12 (HVM), arm64, SSD Volume Type, user 'admin', become 'sudo'
  instance_type                        = "t4g.nano"                                       # 500MB RAM, 2 CPU, 8GB EBS
  public_key_name                      = "id-rsa-starter-kit-deploy"                      # Name of the SSH public key
  public_key_path                      = "./public_keys/id_rsa_starter_kit_deploy.pub"    # Path to the public SSH key file

  # Instance termination and shutdown behavior
  instance_initiated_shutdown_behavior = "stop"                                           # Ensure the instance stops rather than terminates on OS shutdown
  disable_api_termination              = true                                             # Enable termination protection
  disable_api_stop                     = false                                            # Enables stop protection

  # Network VPC configuration
  subnet_ids = data.terraform_remote_state.shared.outputs.subnet_ids     # List of subnet IDs to launch the instance in
  security_group_ids = [
    module.security_groups.allow_http_s_id,     # Allow HTTP and HTTPS traffic
    module.security_groups.allow_ssh_id         # Allow SSH traffic
  ]

  associate_public_ip_address = false   # Associate a public IPv4 address with the instance
  ipv6_address_count          = 1       # Number of IPv6 addresses to assign to the instance

  # Tags for the instance
  tags = {
    Name        = "develop.starter-kit.io"
    Environment = "DEV"
  }
}
