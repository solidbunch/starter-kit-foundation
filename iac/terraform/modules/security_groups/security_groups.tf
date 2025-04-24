resource "aws_security_group" "allow_http_s" {
  name        = "Allow HTTP(s)"
  description = "Allow HTTP and HTTPS inbound traffic"

  # IPv4 HTTP
  ingress {
    description = "HTTP (IPv4)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # IPv6 HTTP
  ingress {
    description = "HTTP (IPv6)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }

  # IPv4 HTTPS
  ingress {
    description = "HTTPS (IPv4)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # IPv6 HTTPS
  ingress {
    description = "HTTPS (IPv6)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }

  # Egress for all traffic (IPv4 and IPv6)
  egress {
    from_port         = 0
    to_port           = 0
    protocol          = "-1"
    cidr_blocks       = ["0.0.0.0/0"]
    ipv6_cidr_blocks  = ["::/0"]
  }

  tags = {
    Name = "ForWeb"
  }
}

resource "aws_security_group" "allow_ssh" {
  name        = "Allow SSH"
  description = "Allow SSH inbound traffic"

  # IPv4 SSH
  ingress {
    description = "SSH (IPv4)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # IPv6 SSH
  ingress {
    description = "SSH (IPv6)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "ForSSH"
  }
}
