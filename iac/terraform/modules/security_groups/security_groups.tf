# Security Group for HTTP and HTTPS traffic
resource "aws_security_group" "allow_http_s" {
  name        = "${var.environment}-allow-web"
  description = "Allow web inbound traffic for ${var.environment}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.web_ports
    content {
      description      = "Allow web traffic on port ${ingress.value}"
      from_port        = ingress.value
      to_port          = ingress.value
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  egress {
    from_port         = 0
    to_port           = 0
    protocol          = "-1"
    cidr_blocks       = ["0.0.0.0/0"]
    ipv6_cidr_blocks  = ["::/0"]
  }

  tags = {
    Name = "${var.environment} Allow Web"
  }
}

# Security Group for SSH traffic
resource "aws_security_group" "allow_ssh" {
  name        = "${var.environment}-allow-ssh"
  description = "Allow SSH inbound traffic for ${var.environment}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ssh_ports
    content {
      description      = "Allow SSH traffic on port ${ingress.value}"
      from_port        = ingress.value
      to_port          = ingress.value
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  egress {
    from_port         = 0
    to_port           = 0
    protocol          = "-1"
    cidr_blocks       = ["0.0.0.0/0"]
    ipv6_cidr_blocks  = ["::/0"]
  }

  tags = {
    Name = "${var.environment} Allow SSH"
  }
}
