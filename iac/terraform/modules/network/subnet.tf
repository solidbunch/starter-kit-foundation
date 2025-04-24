resource "aws_subnet" "subnet_a" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.1.0/24"
  ipv6_cidr_block   = cidrsubnet(aws_vpc.main_vpc.ipv6_cidr_block, 8, 0)
  availability_zone = "eu-central-1a"

  tags = {
    Name = "subnet_a"
  }
}

resource "aws_subnet" "subnet_b" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24"
  ipv6_cidr_block   = cidrsubnet(aws_vpc.main_vpc.ipv6_cidr_block, 8, 1)
  availability_zone = "eu-central-1b"

  tags = {
    Name = "subnet_b"
  }
}

resource "aws_subnet" "subnet_c" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.3.0/24"
  ipv6_cidr_block   = cidrsubnet(aws_vpc.main_vpc.ipv6_cidr_block, 8, 2)
  availability_zone = "eu-central-1c"

  tags = {
    Name = "subnet_c"
  }
}
