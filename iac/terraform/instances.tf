# Create an EC2 instances
resource "aws_instance" "develop-server" {
  ami                    = "ami-0fc02b454efabb390" # Ubuntu Server 22.04 LTS (HVM) 64-bit (Arm), SSD Volume Type
  instance_type          = "t4g.micro"
  vpc_security_group_ids = [aws_security_group.allow_http_s.id, aws_security_group.allow_ssh.id]
  key_name               = aws_key_pair.deploy.key_name

  tags = {
    Name          = "starter-kit.io DEV"
    Environment   = "Development"
  }

  root_block_device {
    volume_type = "gp2"  # General Purpose SSD
    volume_size = 8      # Size in GB
  }
}

resource "aws_instance" "develop2-server" {
  ami                    = "ami-01c3c86584374c23b" # alpine-3.19.1-aarch64-uefi-cloudinit-r0 64-bit (Arm), SSD Volume Type
  instance_type          = "t4g.nano"
  vpc_security_group_ids = [aws_security_group.allow_http_s.id, aws_security_group.allow_ssh.id]
  key_name               = aws_key_pair.deploy.key_name

  tags = {
    Name          = "starter-kit.io DEV2"
    Environment   = "Development"
  }

  root_block_device {
    volume_type = "gp2"  # General Purpose SSD
    volume_size = 8      # Size in GB
  }
}

/*resource "aws_instance" "production-server" {
  ami                    = "ami-0fc02b454efabb390" # Ubuntu Server 22.04 LTS (HVM) 64-bit (Arm), SSD Volume Type
  instance_type          = "t4g.micro"
  vpc_security_group_ids = [aws_security_group.allow_http_s.id, aws_security_group.allow_ssh.id]
  key_name               = aws_key_pair.deploy.key_name

  tags = {
    Name          = "starter-kit.io PROD"
    Environment   = "Production"
  }

  root_block_device {
    volume_type = "gp2"  # General Purpose SSD
    volume_size = 8      # Size in GB
  }
}*/

output "develop_ip_addr" {
  value = aws_instance.develop2-server.public_ip
}

/*output "prod_ip_addr" {
  value = aws_instance.production-server.public_ip
}*/
