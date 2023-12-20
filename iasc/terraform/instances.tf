# Create an EC2 instances
resource "aws_instance" "develop-server" {
  ami                    = "ami-06dd92ecc74fdfb36" # Ubuntu Server 22.04 LTS (HVM), SSD Volume Type
  instance_type          = "t2.small"
  vpc_security_group_ids = [aws_security_group.allow_http_s.id, aws_security_group.allow_ssh.id]
  key_name               = aws_key_pair.deploy.key_name

  tags = {
    Name          = "starter-kit.io DEV"
    Environment   = "Development"
  }

  root_block_device {
    volume_type = "gp3"  # General Purpose SSD
    volume_size = 10     # Size in GB
  }
}

resource "aws_instance" "production-server" {
  ami                    = "ami-06dd92ecc74fdfb36" # Ubuntu Server 22.04 LTS (HVM), SSD Volume Type
  instance_type          = "t2.small"
  vpc_security_group_ids = [aws_security_group.allow_http_s.id, aws_security_group.allow_ssh.id]
  key_name               = aws_key_pair.deploy.key_name

  tags = {
    Name          = "starter-kit.io PROD"
    Environment   = "Production"
  }

  root_block_device {
    volume_type = "gp3"  # General Purpose SSD
    volume_size = 10     # Size in GB
  }
}

output "develop_ip_addr" {
  value = aws_instance.develop-server.public_ip
}

output "prod_ip_addr" {
  value = aws_instance.production-server.public_ip
}
