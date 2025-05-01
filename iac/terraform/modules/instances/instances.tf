# Create EC2 instance
resource "aws_instance" "this" {
  ami                                  = var.instance_ami
  instance_type                        = var.instance_type
  instance_initiated_shutdown_behavior = var.instance_initiated_shutdown_behavior
  disable_api_termination              = var.disable_api_termination
  disable_api_stop                     = var.disable_api_stop

  key_name                             = var.key_name

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
