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
  source      = "../../modules/security_groups"
  environment = "PROD"
  vpc_id      = data.terraform_remote_state.shared.outputs.vpc_id
  web_ports   = [80, 443]
  ssh_ports   = [22]
}

# Launch EC2 instances
module "instances" {
  source = "../../modules/instances"

  # Instance configuration
  # If you have 'Error: collecting instance settings: couldn't find resource' just check AMI id, it changes time to time
  instance_ami                         = "ami-0393eeb161ec86a1a"                              # Debian 12 (HVM), arm64, SSD Volume Type, user 'admin', become 'sudo'
  instance_type                        = "t4g.nano"                                           # 500MB RAM, 2 CPU, 8GB EBS
  key_name                             = "id-rsa-starter-kit-deploy"                          # Name of the existing SSH key pair

  # Instance termination and shutdown behavior
  instance_initiated_shutdown_behavior = "stop"                                              # Ensure the instance stops rather than terminates on OS shutdown
  disable_api_termination              = true                                                # Enable termination protection
  disable_api_stop                     = true                                                # Enables stop protection

  # Network VPC configuration
  subnet_ids = data.terraform_remote_state.shared.outputs.subnet_ids     # List of subnet IDs to launch the instance in
  security_group_ids = [
    module.security_groups.allow_http_s_id,     # Allow HTTP and HTTPS traffic
    module.security_groups.allow_ssh_id         # Allow SSH traffic
  ]

  associate_public_ip_address = true   # Associate a public IPv4 address with the instance
  ipv6_address_count          = 1       # Number of IPv6 addresses to assign to the instance

  #root_block_device {
  #  volume_type = "gp2"  # General Purpose SSD
  #  volume_size = 25     # Size in GB
  #}

  # Tags for the instance
  tags = {
    Name        = "starter-kit.io"
    Environment = "PROD"
  }
}
