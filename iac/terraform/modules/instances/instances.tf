# Upload SSH public key to AWS
resource "aws_key_pair" "deploy" {
  key_name   = var.public_key_name
  public_key = file(var.public_key_path)
}

# Create EC2 instance
resource "aws_instance" "this" {
  ami                                  = var.instance_ami
  instance_type                        = var.instance_type
  instance_initiated_shutdown_behavior = var.instance_initiated_shutdown_behavior
  disable_api_termination              = var.disable_api_termination
  disable_api_stop                     = var.disable_api_stop

  key_name                             = aws_key_pair.deploy.key_name

  vpc_security_group_ids               = var.security_group_ids
  subnet_id                            = var.subnet_ids[0]

  associate_public_ip_address          = var.associate_public_ip_address
  ipv6_address_count                   = var.ipv6_address_count

  tags = var.tags
}

# Output public IP of the instance
output "public_ip" {
  value = aws_instance.this.public_ip
}
output "ipv6" {
  value = aws_instance.this.ipv6_addresses[0]
}

# Create an EC2 instances
# If you have 'Error: collecting instance settings: couldn't find resource' just check AMI id, it changes time to time

#"ami-04bd057ffbd865312" # Debian 12 (HVM), arm64, SSD Volume Type, user 'admin', become 'sudo'

/*resource "aws_instance" "production-server" {
  provider               = aws.frankfurt # Refer to the aliased provider
  ami                    = "ami-0c758b376a9cf7862" # Debian 12 (HVM), SSD Volume Type, user 'admin', become 'sudo'
  instance_type          = "t4g.nano"
  vpc_security_group_ids = [aws_security_group.allow_http_s.id, aws_security_group.allow_ssh.id]
  key_name               = aws_key_pair.deploy.key_name

  tags = {
    Name          = "starter-kit.io"
    Environment   = "PROD"
  }

  root_block_device {
    volume_type = "gp2"  # General Purpose SSD
    volume_size = 25     # Size in GB
  }

  # Ensure the instance stops rather than terminates on OS shutdown
  instance_initiated_shutdown_behavior = "stop"

  # Enable termination protection
  disable_api_termination = true

  # Enables stop protection
  disable_api_stop = true
}*/

#output "develop_ip_addr" {
#  value = aws_instance.develop-server.public_ip
#}

/*output "prod_ip_addr" {
  value = aws_instance.production-server.public_ip
}*/

# Define deploy key
#resource "aws_key_pair" "deploy" {
#  key_name = "deploy-key"
#  public_key = file("./public_keys/id_rsa_starter_kit_deploy.pub")
  # make terraform import aws_key_pair.deploy deploy-key
#}

/**
 * If IP address was renew, follow this steps:
 * 1. Update DNS for selected domains
 * 2. Update SSH config in git deploy variables
 * 3. Update local SSH config
 * 4. Update Ansible inventory if needed
**/
