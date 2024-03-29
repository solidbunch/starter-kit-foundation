# Create an EC2 instances
# If you have 'Error: collecting instance settings: couldn't find resource' just check AMI id, it changes time to time

resource "aws_instance" "develop-server" {
  provider               = aws.frankfurt # Refer to the aliased provider
  ami                    = "ami-04bd057ffbd865312" # Debian 12 (HVM), arm64, SSD Volume Type, user 'admin', become 'sudo'
  instance_type          = "t4g.nano"
  vpc_security_group_ids = [aws_security_group.allow_http_s.id, aws_security_group.allow_ssh.id]
  key_name               = aws_key_pair.deploy.key_name

  tags = {
    Name          = "develop.starter-kit.io"
    Environment   = "DEV"
  }

  root_block_device {
    volume_type = "gp2"  # General Purpose SSD
    volume_size = 20     # Size in GB
  }

  # Ensure the instance stops rather than terminates on OS shutdown
  instance_initiated_shutdown_behavior = "stop"

  # Enable termination protection
  disable_api_termination = true
}

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

output "develop_ip_addr" {
  value = aws_instance.develop-server.public_ip
}

/*output "prod_ip_addr" {
  value = aws_instance.production-server.public_ip
}*/

/**
 * If IP address was renew, follow this steps:
 * 1. Update DNS for selected domains
 * 2. Update SSH config in git deploy variables
 * 3. Update local SSH config
 * 4. Update Ansible inventory if needed
**/
